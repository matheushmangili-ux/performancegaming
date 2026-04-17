<script lang="ts">
	import NeonButton from '$lib/components/cyberpunk/NeonButton.svelte';
	import SeverityBadge from './SeverityBadge.svelte';
	import type { Finding } from '$lib/ipc/tauri';
	import {
		apply,
		cancelConfirm,
		resetApply,
		runApply
	} from '$lib/stores/apply';

	interface Props {
		findings: Finding[];
	}

	let { findings }: Props = $props();

	let selectedFindings = $derived(findings.filter((f) => $apply.selection.has(f.id)));

	async function confirmApply() {
		await runApply(findings, 'fix');
	}

	function close() {
		if ($apply.phase === 'applying') return;
		cancelConfirm();
		resetApply();
	}

	function severityColor(status: string): string {
		switch (status) {
			case 'ok':
				return 'var(--color-neon-lime)';
			case 'failed':
				return 'var(--color-neon-red)';
			case 'running':
				return 'var(--color-neon-cyan)';
			case 'skipped':
				return 'var(--color-fg-muted)';
			default:
				return 'var(--color-fg-secondary)';
		}
	}
</script>

{#if $apply.phase !== 'idle'}
	<div
		class="backdrop"
		role="presentation"
		onclick={close}
		onkeydown={(e) => e.key === 'Escape' && close()}
	>
		<div
			class="dialog"
			role="dialog"
			aria-modal="true"
			tabindex="-1"
			onclick={(e) => e.stopPropagation()}
			onkeydown={(e) => e.stopPropagation()}
		>
			<header class="dialog-head">
				{#if $apply.phase === 'confirming'}
					<h2>CONFIRM {$apply.mode.toUpperCase()}</h2>
				{:else if $apply.phase === 'applying'}
					<h2>APPLYING · {$apply.currentIndex + 1}/{$apply.totalToApply}</h2>
				{:else if $apply.phase === 'complete'}
					<h2>COMPLETE</h2>
				{:else if $apply.phase === 'error'}
					<h2 class="err">ERROR</h2>
				{/if}
			</header>

			<div class="dialog-body">
				{#if $apply.phase === 'confirming'}
					<p class="summary">
						<strong>{selectedFindings.length}</strong> item{selectedFindings.length === 1 ? '' : 's'}
						will be applied. A <strong>System Restore Point</strong> will be created before
						changes. Each command runs via <code>cmd.exe /c</code> with admin privileges.
					</p>
					<ul class="preview">
						{#each selectedFindings.slice(0, 8) as f (f.id)}
							<li>
								<SeverityBadge severity={f.severity} size="sm" />
								<span class="ftitle">{f.title}</span>
							</li>
						{/each}
						{#if selectedFindings.length > 8}
							<li class="more">+ {selectedFindings.length - 8} more…</li>
						{/if}
					</ul>
					<p class="warn">
						⚠ Some changes take effect only after a reboot. Avoid running during a game.
					</p>
				{:else if $apply.phase === 'applying' || $apply.phase === 'complete'}
					<div class="rp">
						<span class="rp-lbl">RESTORE POINT:</span>
						{#if $apply.restorePoint.status === 'idle'}
							<span class="rp-val muted">pending</span>
						{:else if $apply.restorePoint.status === 'creating'}
							<span class="rp-val cyan">creating…</span>
						{:else if $apply.restorePoint.status === 'created'}
							<span class="rp-val ok">✓ {$apply.restorePoint.label}</span>
						{:else}
							<span class="rp-val warn"
								>skipped{$apply.restorePoint.reason
									? ` (${$apply.restorePoint.reason})`
									: ''}</span
							>
						{/if}
					</div>

					<div class="progress-bar">
						<div
							class="progress-fill"
							style="width: {$apply.totalToApply > 0
								? ($apply.results.filter((r) => r.status !== 'running').length /
										$apply.totalToApply) *
									100
								: 0}%"
						></div>
					</div>

					<ul class="items">
						{#each $apply.results as r (r.id)}
							<li class="item item--{r.status}" style="--ic: {severityColor(r.status)}">
								<span class="dot"></span>
								<span class="name">{r.title}</span>
								<span class="st">{r.status}</span>
							</li>
						{/each}
					</ul>

					{#if $apply.phase === 'complete' && $apply.summary}
						<dl class="totals">
							<div><dt>APPLIED</dt><dd class="ok">{$apply.summary.applied}</dd></div>
							<div><dt>FAILED</dt><dd class="err">{$apply.summary.failed}</dd></div>
							<div><dt>SKIPPED</dt><dd>{$apply.summary.skipped}</dd></div>
						</dl>
						<p class="reboot-hint">
							Most changes take effect immediately. Some require a reboot — if FPS feels the
							same, reboot and re-test.
						</p>
					{/if}
				{:else if $apply.phase === 'error'}
					<pre class="err-msg">{$apply.error}</pre>
				{/if}
			</div>

			<footer class="dialog-foot">
				{#if $apply.phase === 'confirming'}
					<NeonButton variant="ghost" onclick={cancelConfirm}>Cancel</NeonButton>
					<NeonButton variant="success" onclick={confirmApply}
						>Apply {selectedFindings.length}</NeonButton
					>
				{:else if $apply.phase === 'applying'}
					<NeonButton variant="ghost" disabled>Running…</NeonButton>
				{:else if $apply.phase === 'complete' || $apply.phase === 'error'}
					<NeonButton variant="ghost" onclick={close}>Close</NeonButton>
				{/if}
			</footer>
		</div>
	</div>
{/if}

<style>
	.backdrop {
		position: fixed;
		inset: 0;
		background: rgba(0, 0, 0, 0.72);
		backdrop-filter: blur(6px);
		z-index: var(--z-modal);
		display: grid;
		place-items: center;
		padding: var(--space-4);
	}
	.dialog {
		width: 100%;
		max-width: 640px;
		max-height: 90vh;
		display: flex;
		flex-direction: column;
		background: var(--color-bg-surface);
		border: 1px solid var(--color-neon-cyan);
		border-radius: var(--radius-lg);
		box-shadow: var(--glow-cyan-md), var(--shadow-depth-lg);
		overflow: hidden;
	}
	.dialog-head {
		padding: var(--space-4) var(--space-5);
		border-bottom: 1px solid var(--color-border-subtle);
	}
	.dialog-head h2 {
		margin: 0;
		font-size: var(--fs-lg);
		letter-spacing: var(--ls-display);
		color: var(--color-neon-cyan);
	}
	.dialog-head h2.err {
		color: var(--color-neon-red);
	}

	.dialog-body {
		padding: var(--space-5);
		overflow-y: auto;
		flex: 1;
		display: flex;
		flex-direction: column;
		gap: var(--space-4);
	}

	.dialog-foot {
		padding: var(--space-4) var(--space-5);
		display: flex;
		justify-content: flex-end;
		gap: var(--space-3);
		border-top: 1px solid var(--color-border-subtle);
	}

	.summary {
		margin: 0;
		font-size: var(--fs-sm);
		line-height: var(--lh-relaxed);
		color: var(--color-fg-secondary);
	}
	.summary strong {
		color: var(--color-neon-cyan);
	}
	.summary code {
		font-family: var(--font-mono);
		font-size: var(--fs-xs);
		color: var(--color-neon-lime);
	}

	.preview {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
		max-height: 240px;
		overflow-y: auto;
	}
	.preview li {
		display: flex;
		align-items: center;
		gap: var(--space-3);
		padding: var(--space-2);
		background: rgba(0, 0, 0, 0.35);
		border-radius: var(--radius-sm);
	}
	.ftitle {
		font-size: var(--fs-sm);
		color: var(--color-fg-primary);
	}
	.more {
		justify-content: center;
		color: var(--color-fg-muted);
		font-family: var(--font-mono);
		font-size: var(--fs-xs);
	}

	.warn {
		margin: 0;
		padding: var(--space-3);
		background: rgba(255, 179, 0, 0.08);
		border: 1px solid rgba(255, 179, 0, 0.25);
		border-radius: var(--radius-sm);
		color: var(--color-neon-amber);
		font-size: var(--fs-xs);
	}

	.rp {
		display: flex;
		gap: var(--space-3);
		align-items: center;
		font-family: var(--font-mono);
		font-size: var(--fs-xs);
		letter-spacing: var(--ls-wide);
	}
	.rp-lbl {
		color: var(--color-fg-muted);
	}
	.rp-val.muted {
		color: var(--color-fg-muted);
	}
	.rp-val.cyan {
		color: var(--color-neon-cyan);
	}
	.rp-val.ok {
		color: var(--color-neon-lime);
	}
	.rp-val.warn {
		color: var(--color-neon-amber);
	}

	.progress-bar {
		height: 6px;
		background: var(--color-bg-elevated);
		border-radius: var(--radius-pill);
		overflow: hidden;
	}
	.progress-fill {
		height: 100%;
		background: linear-gradient(90deg, var(--color-neon-cyan), var(--color-neon-lime));
		box-shadow: var(--glow-cyan-sm);
		transition: width var(--dur-base) var(--ease-smooth);
	}

	.items {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: 4px;
		max-height: 280px;
		overflow-y: auto;
	}
	.item {
		display: grid;
		grid-template-columns: 10px 1fr auto;
		align-items: center;
		gap: var(--space-3);
		padding: var(--space-2) var(--space-3);
		font-size: var(--fs-sm);
	}
	.item .dot {
		width: 8px;
		height: 8px;
		border-radius: 50%;
		background: var(--ic);
		box-shadow: 0 0 6px var(--ic);
	}
	.item.item--running .dot {
		animation: neon-pulse 1s ease-in-out infinite;
	}
	.item .name {
		color: var(--color-fg-primary);
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.item .st {
		font-family: var(--font-mono);
		font-size: var(--fs-xs);
		letter-spacing: var(--ls-wide);
		color: var(--ic);
		text-transform: uppercase;
	}

	.totals {
		display: grid;
		grid-template-columns: repeat(3, 1fr);
		gap: var(--space-3);
		margin: 0;
		padding: var(--space-3);
		background: rgba(0, 0, 0, 0.3);
		border-radius: var(--radius-md);
	}
	.totals > div {
		text-align: center;
	}
	.totals dt {
		font-family: var(--font-mono);
		font-size: 10px;
		letter-spacing: var(--ls-wider);
		color: var(--color-fg-muted);
	}
	.totals dd {
		margin: 4px 0 0;
		font-family: var(--font-display);
		font-size: var(--fs-2xl);
		font-weight: var(--fw-black);
		color: var(--color-fg-primary);
	}
	.totals dd.ok {
		color: var(--color-neon-lime);
	}
	.totals dd.err {
		color: var(--color-neon-red);
	}

	.reboot-hint {
		margin: 0;
		padding: var(--space-3);
		border: 1px dashed var(--color-border-faint);
		border-radius: var(--radius-sm);
		font-family: var(--font-mono);
		font-size: var(--fs-xs);
		color: var(--color-fg-muted);
	}

	.err-msg {
		margin: 0;
		padding: var(--space-3);
		background: rgba(255, 46, 91, 0.08);
		border: 1px solid rgba(255, 46, 91, 0.4);
		border-radius: var(--radius-sm);
		color: var(--color-neon-red);
		font-family: var(--font-mono);
		font-size: var(--fs-xs);
		white-space: pre-wrap;
		word-break: break-word;
	}
</style>
