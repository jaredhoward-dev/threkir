<script lang="ts">
	import { m } from '#lib/i18n/store.svelte.ts';

	// "Which route?": a tap that landed on several overlapping routes, or on a
	// small cluster, lists them by name instead of opening whichever was drawn
	// on top (decisions § 2611).
	let {
		title,
		items,
		onpick,
		onclose,
	}: {
		title: string;
		items: { id: string; name: string; stats: string }[];
		onpick: (id: string) => void;
		onclose: () => void;
	} = $props();
</script>

<div class="picker" role="dialog" aria-label={title} data-testid="explore-picker">
	<div class="head">
		<h3>{title}</h3>
		<button type="button" class="close" onclick={onclose} aria-label={m('modal.close')}>
			<span class="material-symbols" aria-hidden="true">close</span>
		</button>
	</div>
	<ul>
		{#each items as item (item.id)}
			<li>
				<button type="button" onclick={() => onpick(item.id)} data-testid="explore-picker-{item.id}">
					<span class="name">{item.name}</span>
					<span class="stats">{item.stats}</span>
				</button>
			</li>
		{/each}
	</ul>
</div>

<style>
	.picker {
		width: min(100%, 26rem);
		max-height: 60vh;
		overflow-y: auto;
		padding: var(--space-sm);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		background: var(--color-surface);
		box-shadow: var(--shadow-lg);
	}
	.head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding-inline-start: var(--space-sm);
	}
	h3 {
		margin: 0;
		font-size: 1rem;
		font-weight: 700;
	}
	.close {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: var(--tap-target-min);
		height: var(--tap-target-min);
		border: none;
		border-radius: 50%;
		background: none;
		color: var(--color-text-secondary);
		cursor: pointer;
	}
	ul {
		margin: 0;
		padding: 0;
		list-style: none;
	}
	li button {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		width: 100%;
		min-height: var(--tap-target-min);
		padding: var(--space-xs) var(--space-sm);
		border: none;
		border-radius: var(--radius-sm);
		background: none;
		color: var(--color-text);
		text-align: start;
		cursor: pointer;
	}
	li button:hover,
	li button:focus-visible {
		background: var(--color-bg-secondary);
	}
	.name {
		font-weight: 600;
		overflow-wrap: anywhere;
	}
	.stats {
		color: var(--color-text-secondary);
		font-size: 0.85rem;
	}
</style>
