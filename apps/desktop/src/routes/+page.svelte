<script lang="ts">
	import NeonButton from '$lib/components/cyberpunk/NeonButton.svelte';
	import GlitchText from '$lib/components/cyberpunk/GlitchText.svelte';

	let tagline = 'SYSTEM DIAGNOSTIC // OPTIMIZATION SUITE';
</script>

<section class="hero">
	<div class="brand">
		<h1 class="title">CLOCK<span class="accent">REAPER</span></h1>
		<p class="tagline anim-caret">{tagline}</p>
	</div>

	<div class="actions">
		<NeonButton variant="primary" size="lg" onclick={() => (window.location.href = '/scan')}>
			Run System Scan
		</NeonButton>
		<NeonButton variant="ghost" size="lg" onclick={() => (window.location.href = '/history')}>
			History
		</NeonButton>
		<NeonButton variant="ghost" size="lg" onclick={() => (window.location.href = '/showcase')}>
			Components
		</NeonButton>
	</div>

	<div class="placeholder">
		<GlitchText
			text="WEEK 6 // DUAL-MODE + HISTORY ONLINE"
			tag="span"
			mode="always"
			intensity="subtle"
		/>
	</div>
</section>

<style>
	.hero {
		flex: 1;
		display: grid;
		place-items: center;
		padding: var(--space-16) var(--space-8);
		gap: var(--space-8);
	}

	.brand {
		text-align: center;
	}

	.title {
		font-size: var(--fs-4xl);
		color: var(--color-fg-primary);
		text-shadow:
			0 0 12px var(--color-neon-cyan),
			0 0 2px var(--color-neon-cyan);
		animation: neon-pulse 3s var(--ease-smooth) infinite;
	}

	.accent {
		color: var(--color-neon-magenta);
		text-shadow:
			0 0 12px var(--color-neon-magenta),
			0 0 2px var(--color-neon-magenta);
	}

	.tagline {
		margin-top: var(--space-3);
		font-family: var(--font-mono);
		font-size: var(--fs-sm);
		letter-spacing: var(--ls-wider);
		color: var(--color-neon-cyan-soft);
		text-transform: uppercase;
	}

	.actions {
		display: flex;
		gap: var(--space-4);
		margin-top: var(--space-2);
	}

	.placeholder {
		color: var(--color-fg-muted);
		font-family: var(--font-mono);
		font-size: var(--fs-xs);
		letter-spacing: var(--ls-wide);
	}
</style>
