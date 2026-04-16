<script lang="ts">
	import { tick } from 'svelte';

	type Severity = 'info' | 'ok' | 'warn' | 'error' | 'muted';

	export interface LogLine {
		id: string | number;
		text: string;
		severity?: Severity;
		timestamp?: string;
	}

	interface Props {
		lines: LogLine[];
		autoScroll?: boolean;
		maxHeight?: string;
		prompt?: string;
		busy?: boolean;
	}

	let {
		lines,
		autoScroll = true,
		maxHeight = '400px',
		prompt = '>',
		busy = false
	}: Props = $props();

	let container = $state<HTMLElement>();

	$effect(() => {
		if (!autoScroll || !container) return;
		// eslint-disable-next-line @typescript-eslint/no-unused-expressions
		lines.length;
		tick().then(() => {
			if (container) container.scrollTop = container.scrollHeight;
		});
	});

	function severityColor(s: Severity | undefined): string {
		switch (s) {
			case 'ok':
				return 'var(--color-neon-lime)';
			case 'warn':
				return 'var(--color-neon-amber)';
			case 'error':
				return 'var(--color-neon-red)';
			case 'muted':
				return 'var(--color-fg-muted)';
			case 'info':
			default:
				return 'var(--color-neon-cyan)';
		}
	}
</script>

<div
	bind:this={container}
	class="terminal"
	style="max-height: {maxHeight}"
	role="log"
	aria-live="polite"
>
	{#each lines as line (line.id)}
		<div class="line anim-finding-enter">
			{#if line.timestamp}
				<span class="ts">[{line.timestamp}]</span>
			{/if}
			<span class="prompt" style="color: {severityColor(line.severity)}">{prompt}</span>
			<span class="text" style="color: {severityColor(line.severity)}">{line.text}</span>
		</div>
	{/each}
	{#if busy}
		<div class="line busy-line">
			<span class="prompt">{prompt}</span>
			<span class="busy-dots">
				<span>.</span><span>.</span><span>.</span>
			</span>
		</div>
	{/if}
</div>

<style>
	.terminal {
		font-family: var(--font-mono);
		font-size: var(--fs-sm);
		line-height: var(--lh-snug);
		padding: var(--space-4);
		background: rgba(0, 0, 0, 0.55);
		border: 1px solid var(--color-border-faint);
		border-radius: var(--radius-md);
		overflow-y: auto;
		color: var(--color-fg-secondary);
		backdrop-filter: blur(2px);
	}

	.line {
		display: flex;
		gap: var(--space-2);
		padding: 2px 0;
		white-space: pre-wrap;
		word-break: break-word;
	}

	.ts {
		color: var(--color-fg-muted);
		flex-shrink: 0;
	}

	.prompt {
		flex-shrink: 0;
		font-weight: var(--fw-bold);
	}

	.text {
		flex: 1;
	}

	.busy-line {
		color: var(--color-neon-cyan);
	}

	.busy-dots span {
		display: inline-block;
		animation: dot-pulse 1.2s steps(3, end) infinite;
	}
	.busy-dots span:nth-child(2) {
		animation-delay: 0.2s;
	}
	.busy-dots span:nth-child(3) {
		animation-delay: 0.4s;
	}

	@keyframes dot-pulse {
		0%,
		40% {
			opacity: 0.2;
		}
		50% {
			opacity: 1;
		}
		100% {
			opacity: 0.2;
		}
	}
</style>
