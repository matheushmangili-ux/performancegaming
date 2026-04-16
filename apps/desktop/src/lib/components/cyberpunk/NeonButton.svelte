<script lang="ts">
	import type { Snippet } from 'svelte';
	import type { HTMLButtonAttributes } from 'svelte/elements';

	type Variant = 'primary' | 'danger' | 'ghost' | 'success';
	type Size = 'sm' | 'md' | 'lg';

	interface Props extends HTMLButtonAttributes {
		variant?: Variant;
		size?: Size;
		loading?: boolean;
		children?: Snippet;
	}

	let {
		variant = 'primary',
		size = 'md',
		loading = false,
		disabled,
		children,
		onclick,
		...rest
	}: Props = $props();

	let ripples = $state<{ id: number; x: number; y: number }[]>([]);
	let rippleId = 0;

	type ButtonClickEvent = MouseEvent & { currentTarget: EventTarget & HTMLButtonElement };

	function handleClick(e: ButtonClickEvent) {
		if (loading || disabled) return;
		const rect = e.currentTarget.getBoundingClientRect();
		const id = rippleId++;
		ripples = [...ripples, { id, x: e.clientX - rect.left, y: e.clientY - rect.top }];
		setTimeout(() => {
			ripples = ripples.filter((r) => r.id !== id);
		}, 600);
		onclick?.(e as ButtonClickEvent);
	}
</script>

<button
	class="neon-btn neon-btn--{variant} neon-btn--{size}"
	class:is-loading={loading}
	disabled={disabled || loading}
	onclick={handleClick}
	{...rest}
>
	<span class="label" class:is-hidden={loading}>
		{@render children?.()}
	</span>
	{#if loading}
		<span class="spinner" aria-hidden="true"></span>
	{/if}
	{#each ripples as r (r.id)}
		<span class="ripple" style="left: {r.x}px; top: {r.y}px"></span>
	{/each}
</button>

<style>
	.neon-btn {
		position: relative;
		display: inline-flex;
		align-items: center;
		justify-content: center;
		gap: var(--space-2);
		font-family: var(--font-display);
		font-weight: var(--fw-bold);
		letter-spacing: var(--ls-display);
		text-transform: uppercase;
		border: 1px solid currentColor;
		background: transparent;
		cursor: pointer;
		overflow: hidden;
		transition:
			transform var(--dur-fast) var(--ease-sharp),
			background-color var(--dur-base) var(--ease-smooth),
			box-shadow var(--dur-base) var(--ease-smooth),
			color var(--dur-base) var(--ease-smooth);
		clip-path: polygon(
			8px 0,
			100% 0,
			100% calc(100% - 8px),
			calc(100% - 8px) 100%,
			0 100%,
			0 8px
		);
	}

	.neon-btn:focus-visible {
		outline: 2px solid currentColor;
		outline-offset: 3px;
	}

	.neon-btn[disabled] {
		opacity: 0.45;
		cursor: not-allowed;
	}

	/* Sizes */
	.neon-btn--sm {
		font-size: var(--fs-xs);
		padding: var(--space-2) var(--space-4);
	}
	.neon-btn--md {
		font-size: var(--fs-sm);
		padding: var(--space-3) var(--space-6);
	}
	.neon-btn--lg {
		font-size: var(--fs-base);
		padding: var(--space-4) var(--space-8);
	}

	/* Variants */
	.neon-btn--primary {
		color: var(--color-neon-cyan);
		box-shadow: var(--glow-cyan-sm);
	}
	.neon-btn--primary:hover:not([disabled]) {
		background-color: rgba(0, 240, 255, 0.1);
		box-shadow: var(--glow-cyan-md);
		transform: translateY(-1px);
	}
	.neon-btn--primary:active:not([disabled]) {
		transform: translateY(0);
		box-shadow: var(--glow-cyan-sm);
	}

	.neon-btn--danger {
		color: var(--color-neon-red);
		box-shadow: var(--glow-red-md);
	}
	.neon-btn--danger:hover:not([disabled]) {
		background-color: rgba(255, 46, 91, 0.12);
		box-shadow:
			0 0 20px rgba(255, 46, 91, 0.7),
			0 0 4px rgba(255, 46, 91, 1);
		transform: translateY(-1px);
	}

	.neon-btn--success {
		color: var(--color-neon-lime);
		box-shadow: var(--glow-lime-md);
	}
	.neon-btn--success:hover:not([disabled]) {
		background-color: rgba(157, 255, 0, 0.1);
		transform: translateY(-1px);
	}

	.neon-btn--ghost {
		color: var(--color-fg-secondary);
		border-color: var(--color-border-subtle);
		box-shadow: none;
	}
	.neon-btn--ghost:hover:not([disabled]) {
		color: var(--color-neon-cyan);
		border-color: var(--color-neon-cyan);
		background-color: rgba(0, 240, 255, 0.05);
	}

	/* Label + spinner */
	.label {
		display: inline-flex;
		align-items: center;
		gap: var(--space-2);
		transition: opacity var(--dur-fast) var(--ease-sharp);
	}
	.label.is-hidden {
		opacity: 0;
	}

	.spinner {
		position: absolute;
		width: 14px;
		height: 14px;
		border: 2px solid currentColor;
		border-right-color: transparent;
		border-radius: 50%;
		animation: spinner-rotate 0.8s linear infinite;
	}

	@keyframes spinner-rotate {
		to {
			transform: rotate(360deg);
		}
	}

	/* Ripple */
	.ripple {
		position: absolute;
		width: 8px;
		height: 8px;
		border-radius: 50%;
		background: currentColor;
		transform: translate(-50%, -50%);
		pointer-events: none;
		animation: ripple-expand 0.6s var(--ease-smooth) forwards;
	}

	@keyframes ripple-expand {
		to {
			width: 300px;
			height: 300px;
			opacity: 0;
		}
	}
</style>
