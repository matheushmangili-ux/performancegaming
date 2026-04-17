<script lang="ts">
	import type { ScanMode } from '$lib/ipc/tauri';

	interface Props {
		value: ScanMode;
		onChange: (m: ScanMode) => void;
		disabled?: boolean;
	}

	let { value, onChange, disabled = false }: Props = $props();

	const options: Array<{ key: ScanMode; label: string; hint: string }> = [
		{ key: 'gaming', label: 'GAMING', hint: 'GPU · Scheduler · Timer · Rede' },
		{ key: 'general', label: 'GENERAL', hint: 'Services · Telemetry · Startup' },
		{ key: 'all', label: 'ALL', hint: 'Every category' }
	];
</script>

<div class="toggle" role="tablist" aria-label="Scan mode">
	{#each options as opt (opt.key)}
		<button
			type="button"
			role="tab"
			aria-selected={value === opt.key}
			class="opt"
			class:is-active={value === opt.key}
			{disabled}
			onclick={() => onChange(opt.key)}
		>
			<span class="label">{opt.label}</span>
			<span class="hint">{opt.hint}</span>
		</button>
	{/each}
</div>

<style>
	.toggle {
		display: inline-grid;
		grid-auto-flow: column;
		grid-auto-columns: 1fr;
		padding: 2px;
		background: rgba(0, 0, 0, 0.35);
		border: 1px solid var(--color-border-subtle);
		border-radius: var(--radius-md);
		gap: 2px;
	}

	.opt {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 2px;
		padding: var(--space-2) var(--space-4);
		background: transparent;
		border: none;
		cursor: pointer;
		transition: all var(--dur-fast) var(--ease-sharp);
		border-radius: var(--radius-sm);
	}
	.opt[disabled] {
		cursor: not-allowed;
		opacity: 0.4;
	}

	.label {
		font-family: var(--font-display);
		font-size: var(--fs-xs);
		font-weight: var(--fw-bold);
		letter-spacing: var(--ls-display);
		color: var(--color-fg-muted);
	}
	.hint {
		font-family: var(--font-mono);
		font-size: 9px;
		letter-spacing: var(--ls-wide);
		color: var(--color-fg-muted);
		opacity: 0.7;
	}

	.opt:hover:not([disabled]) .label {
		color: var(--color-neon-cyan);
	}

	.opt.is-active {
		background: rgba(0, 240, 255, 0.12);
		box-shadow: inset 0 0 0 1px var(--color-neon-cyan);
	}
	.opt.is-active .label {
		color: var(--color-neon-cyan);
		text-shadow: var(--glow-cyan-xs);
	}
	.opt.is-active .hint {
		color: var(--color-fg-secondary);
		opacity: 1;
	}
</style>
