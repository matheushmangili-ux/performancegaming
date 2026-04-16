<script lang="ts">
	import type { Snippet } from 'svelte';

	interface Props {
		intensity?: 'subtle' | 'medium' | 'strong';
		sweep?: boolean;
		flicker?: boolean;
		children?: Snippet;
	}

	let { intensity = 'subtle', sweep = false, flicker = false, children }: Props = $props();
</script>

<div
	class="scanline-wrap scanline-wrap--{intensity}"
	class:has-sweep={sweep}
	class:has-flicker={flicker}
>
	<div class="content">
		{@render children?.()}
	</div>
	<div class="scanlines" aria-hidden="true"></div>
	{#if sweep}
		<div class="sweep" aria-hidden="true"></div>
	{/if}
</div>

<style>
	.scanline-wrap {
		position: relative;
		display: block;
		overflow: hidden;
	}

	.content {
		position: relative;
		z-index: 1;
	}

	.scanlines {
		position: absolute;
		inset: 0;
		pointer-events: none;
		z-index: 2;
		mix-blend-mode: overlay;
	}

	.scanline-wrap--subtle .scanlines {
		background: repeating-linear-gradient(
			0deg,
			rgba(0, 240, 255, 0.03) 0,
			rgba(0, 240, 255, 0.03) 1px,
			transparent 1px,
			transparent 3px
		);
	}
	.scanline-wrap--medium .scanlines {
		background: repeating-linear-gradient(
			0deg,
			rgba(0, 240, 255, 0.08) 0,
			rgba(0, 240, 255, 0.08) 1px,
			transparent 1px,
			transparent 2px
		);
	}
	.scanline-wrap--strong .scanlines {
		background: repeating-linear-gradient(
			0deg,
			rgba(0, 240, 255, 0.14) 0,
			rgba(0, 240, 255, 0.14) 2px,
			transparent 2px,
			transparent 4px
		);
	}

	.has-flicker .content {
		animation: crt-flicker 4s steps(1, end) infinite;
	}

	.sweep {
		position: absolute;
		left: 0;
		right: 0;
		height: 32%;
		pointer-events: none;
		z-index: 3;
		background: linear-gradient(
			to bottom,
			transparent 0%,
			rgba(0, 240, 255, 0.12) 50%,
			transparent 100%
		);
		animation: scanline-drift 4s linear infinite;
	}
</style>
