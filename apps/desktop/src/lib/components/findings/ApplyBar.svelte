<script lang="ts">
	import NeonButton from '$lib/components/cyberpunk/NeonButton.svelte';
	import type { Finding } from '$lib/ipc/tauri';
	import {
		apply,
		selectionCount,
		clearSelection,
		selectAll,
		selectBySeverity,
		startConfirm
	} from '$lib/stores/apply';

	interface Props {
		findings: Finding[];
		disabled?: boolean;
	}

	let { findings, disabled = false }: Props = $props();

	const fixable = $derived(findings.filter((f) => f.fix_cmd));
</script>

{#if fixable.length > 0}
	<div class="bar" class:is-active={$selectionCount > 0}>
		<div class="left">
			<div class="count-block">
				<span class="count">{$selectionCount}</span>
				<span class="lbl">selected · {fixable.length} fixable</span>
			</div>
			<div class="quick">
				<button
					class="q-btn"
					onclick={() => selectBySeverity(findings, ['CRITICO'])}
					disabled={disabled}
				>
					Critical only
				</button>
				<button
					class="q-btn"
					onclick={() => selectBySeverity(findings, ['CRITICO', 'ALTO'])}
					disabled={disabled}
				>
					Balanced
				</button>
				<button class="q-btn" onclick={() => selectAll(findings)} disabled={disabled}>
					All
				</button>
				<button
					class="q-btn q-btn--ghost"
					onclick={clearSelection}
					disabled={disabled || $selectionCount === 0}
				>
					Clear
				</button>
			</div>
		</div>
		<div class="right">
			<NeonButton
				variant="success"
				size="md"
				disabled={disabled || $selectionCount === 0 || $apply.phase === 'applying'}
				onclick={() => startConfirm('fix')}
			>
				Apply {$selectionCount > 0 ? $selectionCount : ''} Fix{$selectionCount === 1 ? '' : 'es'}
			</NeonButton>
		</div>
	</div>
{/if}

<style>
	.bar {
		position: sticky;
		bottom: var(--space-4);
		z-index: var(--z-sticky);
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-4);
		padding: var(--space-4) var(--space-5);
		background: var(--gradient-panel);
		border: 1px solid var(--color-border-subtle);
		border-radius: var(--radius-lg);
		backdrop-filter: blur(12px);
		box-shadow: var(--shadow-depth-md);
		transition: border-color var(--dur-base) var(--ease-smooth);
	}
	.bar.is-active {
		border-color: var(--color-neon-cyan);
		box-shadow: var(--shadow-depth-md), 0 0 24px rgba(0, 240, 255, 0.25);
	}

	.left {
		display: flex;
		align-items: center;
		gap: var(--space-5);
		flex: 1;
		flex-wrap: wrap;
	}

	.count-block {
		display: flex;
		align-items: baseline;
		gap: var(--space-2);
	}
	.count {
		font-family: var(--font-display);
		font-size: var(--fs-2xl);
		font-weight: var(--fw-black);
		color: var(--color-neon-cyan);
		text-shadow: var(--glow-cyan-sm);
	}
	.lbl {
		font-family: var(--font-mono);
		font-size: var(--fs-xs);
		letter-spacing: var(--ls-wide);
		color: var(--color-fg-muted);
		text-transform: uppercase;
	}

	.quick {
		display: flex;
		gap: var(--space-2);
		flex-wrap: wrap;
	}

	.q-btn {
		padding: 4px 10px;
		font-family: var(--font-mono);
		font-size: 10px;
		font-weight: var(--fw-bold);
		letter-spacing: var(--ls-wide);
		color: var(--color-fg-secondary);
		background: transparent;
		border: 1px solid var(--color-border-faint);
		border-radius: var(--radius-sm);
		cursor: pointer;
		text-transform: uppercase;
		transition: all var(--dur-fast) var(--ease-sharp);
	}
	.q-btn:hover:not([disabled]) {
		color: var(--color-neon-cyan);
		border-color: var(--color-neon-cyan);
	}
	.q-btn[disabled] {
		opacity: 0.3;
		cursor: not-allowed;
	}

	.q-btn--ghost {
		color: var(--color-fg-muted);
	}

	.right {
		flex-shrink: 0;
	}
</style>
