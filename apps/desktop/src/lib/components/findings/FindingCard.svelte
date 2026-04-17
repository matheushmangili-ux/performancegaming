<script lang="ts">
	import type { Finding } from '$lib/ipc/tauri';
	import SeverityBadge from './SeverityBadge.svelte';

	interface Props {
		finding: Finding;
		index?: number;
		selected?: boolean;
		onToggleSelect?: (id: string) => void;
	}

	let { finding, index = 0, selected = false, onToggleSelect }: Props = $props();

	let expanded = $state(false);
	const canFix = $derived(!!finding.fix_cmd);

	function toggle() {
		expanded = !expanded;
	}

	function handleToggleSelect() {
		if (!canFix) return;
		onToggleSelect?.(finding.id);
	}
</script>

<article
	class="finding finding--{finding.severity.toLowerCase()} anim-finding-enter"
	class:is-selected={selected}
	style="animation-delay: {Math.min(index * 40, 400)}ms"
>
	<div class="header">
		<label class="check" class:is-disabled={!canFix}>
			<input
				type="checkbox"
				checked={selected}
				disabled={!canFix}
				onchange={handleToggleSelect}
				aria-label="Select finding for fix"
			/>
			<span class="box" aria-hidden="true">
				{#if selected}<span class="check-mark">✓</span>{/if}
			</span>
		</label>
		<button class="body-btn" type="button" onclick={toggle} aria-expanded={expanded}>
			<div class="row-top">
				<SeverityBadge severity={finding.severity} />
				<span class="category">{finding.category}</span>
				{#if !canFix}
					<span class="no-fix">INFO · no fix</span>
				{/if}
				<span class="chevron" class:is-open={expanded}>▸</span>
			</div>
			<h3 class="title">{finding.title}</h3>
			<p class="current">
				<span class="lbl">CURRENT:</span>
				<span class="val">{finding.current}</span>
			</p>
		</button>
	</div>

	{#if expanded}
		<div class="body">
			<section class="block">
				<h4>Why it matters</h4>
				<p>{finding.why}</p>
			</section>
			<section class="block">
				<h4>Expected impact</h4>
				<p class="impact">{finding.impact}</p>
			</section>
			{#if finding.fix_cmd}
				<section class="block">
					<h4>Fix command</h4>
					<pre><code>{finding.fix_cmd}</code></pre>
				</section>
			{/if}
			{#if finding.revert_cmd}
				<section class="block block--muted">
					<h4>Revert command</h4>
					<pre><code>{finding.revert_cmd}</code></pre>
				</section>
			{/if}
		</div>
	{/if}
</article>

<style>
	.finding {
		display: block;
		background: var(--gradient-panel);
		border: 1px solid var(--color-border-faint);
		border-left-width: 3px;
		border-radius: var(--radius-md);
		overflow: hidden;
		transition:
			border-color var(--dur-base) var(--ease-smooth),
			box-shadow var(--dur-base) var(--ease-smooth);
	}

	.finding--critico {
		border-left-color: var(--color-severity-critical);
	}
	.finding--alto {
		border-left-color: var(--color-severity-high);
	}
	.finding--medio {
		border-left-color: var(--color-severity-medium);
	}
	.finding--info {
		border-left-color: var(--color-severity-info);
	}
	.finding--ok {
		border-left-color: var(--color-severity-ok);
	}

	.finding:hover {
		border-color: var(--color-border-strong);
	}
	.finding--critico:hover {
		box-shadow: 0 0 16px rgba(255, 46, 91, 0.25);
	}

	.header {
		display: flex;
		align-items: flex-start;
		gap: var(--space-3);
		padding: var(--space-4);
		width: 100%;
	}

	.check {
		flex-shrink: 0;
		display: inline-flex;
		align-items: center;
		justify-content: center;
		cursor: pointer;
		padding: 4px;
		margin-top: 2px;
	}
	.check.is-disabled {
		cursor: not-allowed;
		opacity: 0.35;
	}
	.check input {
		position: absolute;
		opacity: 0;
		pointer-events: none;
	}
	.check .box {
		width: 18px;
		height: 18px;
		border: 1px solid var(--color-border-strong);
		border-radius: var(--radius-sm);
		background: rgba(0, 0, 0, 0.4);
		display: inline-flex;
		align-items: center;
		justify-content: center;
		transition: all var(--dur-fast) var(--ease-sharp);
	}
	.check:hover:not(.is-disabled) .box {
		border-color: var(--color-neon-cyan);
		box-shadow: var(--glow-cyan-xs);
	}
	.check input:checked ~ .box {
		background: var(--color-neon-cyan);
		border-color: var(--color-neon-cyan);
		box-shadow: var(--glow-cyan-sm);
	}
	.check-mark {
		color: var(--color-fg-on-neon);
		font-size: 12px;
		font-weight: var(--fw-black);
		line-height: 1;
	}
	.check input:focus-visible ~ .box {
		outline: 2px solid var(--color-neon-cyan);
		outline-offset: 2px;
	}

	.body-btn {
		flex: 1;
		text-align: left;
		background: transparent;
		border: none;
		cursor: pointer;
		color: inherit;
		padding: 0;
		min-width: 0;
	}

	.body-btn:focus-visible {
		outline: 2px solid var(--color-neon-cyan);
		outline-offset: 2px;
		border-radius: var(--radius-sm);
	}

	.no-fix {
		font-family: var(--font-mono);
		font-size: 10px;
		letter-spacing: var(--ls-wide);
		color: var(--color-fg-muted);
		padding: 1px 6px;
		border: 1px solid var(--color-border-faint);
		border-radius: var(--radius-sm);
	}

	.finding.is-selected {
		background:
			linear-gradient(to right, rgba(0, 240, 255, 0.06), transparent 40%),
			var(--gradient-panel);
		border-color: var(--color-border-strong);
	}

	.row-top {
		display: flex;
		align-items: center;
		gap: var(--space-3);
		margin-bottom: var(--space-2);
	}

	.category {
		flex: 1;
		font-family: var(--font-mono);
		font-size: var(--fs-xs);
		letter-spacing: var(--ls-wide);
		color: var(--color-fg-muted);
		text-transform: uppercase;
	}

	.chevron {
		font-size: var(--fs-sm);
		color: var(--color-fg-muted);
		transition: transform var(--dur-fast) var(--ease-sharp);
	}
	.chevron.is-open {
		transform: rotate(90deg);
	}

	.title {
		margin: 0;
		font-family: var(--font-display);
		font-size: var(--fs-base);
		letter-spacing: var(--ls-wide);
		color: var(--color-fg-primary);
		text-transform: uppercase;
	}

	.current {
		margin: var(--space-2) 0 0;
		font-family: var(--font-mono);
		font-size: var(--fs-sm);
		color: var(--color-fg-secondary);
	}
	.lbl {
		color: var(--color-fg-muted);
		margin-right: var(--space-2);
	}

	.body {
		padding: 0 var(--space-4) var(--space-4);
		border-top: 1px solid var(--color-border-faint);
		display: flex;
		flex-direction: column;
		gap: var(--space-4);
	}

	.block h4 {
		margin: var(--space-3) 0 var(--space-2);
		font-family: var(--font-mono);
		font-size: var(--fs-xs);
		letter-spacing: var(--ls-wider);
		color: var(--color-neon-cyan);
	}
	.block p {
		margin: 0;
		font-size: var(--fs-sm);
		color: var(--color-fg-secondary);
		line-height: var(--lh-relaxed);
	}
	.impact {
		color: var(--color-neon-lime);
	}

	.block--muted h4 {
		color: var(--color-fg-muted);
	}

	pre {
		margin: 0;
		padding: var(--space-3);
		background: rgba(0, 0, 0, 0.5);
		border: 1px solid var(--color-border-faint);
		border-radius: var(--radius-sm);
		overflow-x: auto;
		font-size: var(--fs-xs);
		color: var(--color-fg-primary);
	}
	code {
		font-family: var(--font-mono);
	}
</style>
