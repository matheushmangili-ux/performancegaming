<script lang="ts">
	import type { Severity } from '$lib/ipc/tauri';

	interface Props {
		severity: Severity;
		size?: 'sm' | 'md';
	}

	let { severity, size = 'md' }: Props = $props();

	const labels: Record<Severity, string> = {
		CRITICO: 'CRITICAL',
		ALTO: 'HIGH',
		MEDIO: 'MEDIUM',
		INFO: 'INFO',
		OK: 'OK'
	};
</script>

<span class="badge badge--{severity.toLowerCase()} badge--{size}">
	{labels[severity]}
</span>

<style>
	.badge {
		display: inline-flex;
		align-items: center;
		padding: 2px 8px;
		border: 1px solid currentColor;
		border-radius: var(--radius-sm);
		font-family: var(--font-mono);
		font-weight: var(--fw-bold);
		letter-spacing: var(--ls-wider);
		text-transform: uppercase;
		background: rgba(0, 0, 0, 0.3);
	}
	.badge--sm {
		font-size: 9px;
		padding: 1px 6px;
	}
	.badge--md {
		font-size: var(--fs-xs);
	}

	.badge--critico {
		color: var(--color-severity-critical);
		box-shadow: var(--glow-red-md);
		animation: severity-ring 1.4s var(--ease-smooth);
	}
	.badge--alto {
		color: var(--color-severity-high);
		box-shadow: var(--glow-amber-md);
	}
	.badge--medio {
		color: var(--color-severity-medium);
	}
	.badge--info {
		color: var(--color-severity-info);
	}
	.badge--ok {
		color: var(--color-severity-ok);
		box-shadow: var(--glow-lime-md);
	}
</style>
