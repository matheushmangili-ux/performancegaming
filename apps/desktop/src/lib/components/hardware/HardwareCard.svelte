<script lang="ts">
	import type { HardwareInventory } from '$lib/ipc/tauri';

	interface Props {
		hardware: HardwareInventory | null;
	}

	let { hardware }: Props = $props();
</script>

{#if hardware}
	<section class="hw anim-finding-enter">
		<header class="hw-header">
			<h3>SYSTEM INVENTORY</h3>
		</header>
		<dl class="hw-grid">
			{#if hardware.cpu}
				<div class="row">
					<dt>CPU</dt>
					<dd>{hardware.cpu}</dd>
				</div>
			{/if}
			{#if hardware.gpus && hardware.gpus.length}
				<div class="row">
					<dt>GPU</dt>
					<dd>
						{#each hardware.gpus as gpu (gpu)}
							<div>{gpu}</div>
						{/each}
					</dd>
				</div>
			{/if}
			{#if hardware.ram_gb !== undefined}
				<div class="row">
					<dt>RAM</dt>
					<dd>{hardware.ram_gb} GB</dd>
				</div>
			{/if}
			{#if hardware.motherboard}
				<div class="row">
					<dt>MOBO</dt>
					<dd>{hardware.motherboard}</dd>
				</div>
			{/if}
			{#if hardware.bios}
				<div class="row">
					<dt>BIOS</dt>
					<dd>{hardware.bios}</dd>
				</div>
			{/if}
			{#if hardware.chassis}
				<div class="row">
					<dt>CHASSIS</dt>
					<dd>{hardware.chassis}</dd>
				</div>
			{/if}
		</dl>
	</section>
{/if}

<style>
	.hw {
		background: var(--gradient-panel);
		border: 1px solid var(--color-border-subtle);
		border-radius: var(--radius-lg);
		padding: var(--space-4) var(--space-5);
	}

	.hw-header {
		border-bottom: 1px solid var(--color-border-faint);
		padding-bottom: var(--space-3);
		margin-bottom: var(--space-3);
	}

	.hw-header h3 {
		margin: 0;
		font-size: var(--fs-sm);
		letter-spacing: var(--ls-display);
		color: var(--color-neon-cyan);
	}

	.hw-grid {
		display: grid;
		grid-template-columns: 1fr;
		gap: var(--space-2);
		margin: 0;
	}

	.row {
		display: grid;
		grid-template-columns: 90px 1fr;
		gap: var(--space-3);
		font-family: var(--font-mono);
		font-size: var(--fs-xs);
	}

	dt {
		color: var(--color-fg-muted);
		letter-spacing: var(--ls-wide);
		font-weight: var(--fw-bold);
	}

	dd {
		margin: 0;
		color: var(--color-fg-secondary);
		word-break: break-word;
	}
</style>
