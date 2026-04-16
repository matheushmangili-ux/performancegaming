<script lang="ts">
	interface Props {
		text: string;
		mode?: 'always' | 'hover' | 'once';
		intensity?: 'subtle' | 'strong';
		tag?: 'h1' | 'h2' | 'h3' | 'span' | 'p';
		class?: string;
	}

	let {
		text,
		mode = 'hover',
		intensity = 'subtle',
		tag = 'span',
		class: className = ''
	}: Props = $props();
</script>

<svelte:element
	this={tag}
	class="glitch glitch--{mode} glitch--{intensity} {className}"
	data-text={text}
	aria-label={text}
>
	<span class="glitch__base">{text}</span>
	<span class="glitch__layer glitch__layer--1" aria-hidden="true">{text}</span>
	<span class="glitch__layer glitch__layer--2" aria-hidden="true">{text}</span>
</svelte:element>

<style>
	.glitch {
		position: relative;
		display: inline-block;
		color: var(--color-fg-primary);
	}

	.glitch__base {
		position: relative;
		z-index: 2;
	}

	.glitch__layer {
		position: absolute;
		inset: 0;
		pointer-events: none;
		opacity: 0;
		transition: opacity var(--dur-fast) var(--ease-sharp);
	}

	.glitch__layer--1 {
		color: var(--color-neon-cyan);
		transform: translate(-2px, 1px);
		z-index: 1;
	}
	.glitch__layer--2 {
		color: var(--color-neon-magenta);
		transform: translate(2px, -1px);
		z-index: 1;
	}

	/* Always-on mode — layers visible, animated continuously */
	.glitch--always .glitch__layer {
		opacity: 0.7;
	}
	.glitch--always.glitch--subtle .glitch__layer--1 {
		animation: glitch-skew 3s infinite var(--ease-sharp);
	}
	.glitch--always.glitch--subtle .glitch__layer--2 {
		animation: glitch-skew 3s infinite var(--ease-sharp) reverse;
	}
	.glitch--always.glitch--strong .glitch__layer--1 {
		animation:
			glitch-skew 2s infinite steps(8, end),
			glitch-clip 2s infinite steps(8, end);
	}
	.glitch--always.glitch--strong .glitch__layer--2 {
		animation:
			glitch-skew 2.3s infinite steps(8, end) reverse,
			glitch-clip 2.3s infinite steps(8, end) reverse;
	}

	/* Hover-only mode — triggers on :hover */
	.glitch--hover:hover .glitch__layer {
		opacity: 0.75;
	}
	.glitch--hover.glitch--subtle:hover .glitch__layer--1 {
		animation: glitch-skew 0.45s var(--ease-sharp) infinite;
	}
	.glitch--hover.glitch--subtle:hover .glitch__layer--2 {
		animation: glitch-skew 0.45s var(--ease-sharp) infinite reverse;
	}
	.glitch--hover.glitch--strong:hover .glitch__layer--1 {
		animation:
			glitch-skew 0.3s steps(6, end) infinite,
			glitch-clip 0.3s steps(6, end) infinite;
	}
	.glitch--hover.glitch--strong:hover .glitch__layer--2 {
		animation:
			glitch-skew 0.35s steps(6, end) infinite reverse,
			glitch-clip 0.35s steps(6, end) infinite reverse;
	}

	/* Once mode — single pulse on mount (uses glitch--once, caller can retrigger via key) */
	.glitch--once .glitch__layer {
		opacity: 0.75;
	}
	.glitch--once .glitch__layer--1 {
		animation:
			glitch-skew 0.6s steps(6, end) forwards,
			fade-out 0.6s forwards;
	}
	.glitch--once .glitch__layer--2 {
		animation:
			glitch-skew 0.6s steps(6, end) reverse forwards,
			fade-out 0.6s forwards;
	}

	@keyframes fade-out {
		to {
			opacity: 0;
		}
	}
</style>
