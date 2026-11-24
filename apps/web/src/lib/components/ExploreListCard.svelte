<script lang="ts">
	import type { Snippet } from 'svelte';
	import { m } from '#lib/i18n/store.svelte.ts';

	// A row of the "on the map" list (decisions § 2611): the shape on the left,
	// the whole name, the Official line and the stats on the right. A tap shows
	// it on the map.
	let {
		name,
		official = false,
		detail,
		stats,
		thumbnail,
		onclick,
		testid,
	}: {
		name: string;
		official?: boolean;
		detail?: string | null;
		stats: string;
		thumbnail: Snippet;
		onclick: () => void;
		testid?: string;
	} = $props();
</script>

<button type="button" class="list-card" {onclick} data-testid={testid}>
	<span class="thumb" aria-hidden="true">{@render thumbnail()}</span>
	<span class="body">
		<span class="name">{name}</span>
		{#if official}
			<span class="official">
				<span class="material-symbols" aria-hidden="true">verified</span>
				{m('exploreMap.officialCourse')}
			</span>
		{/if}
		{#if detail}<span class="meta">{detail}</span>{/if}
		<span class="meta">{stats}</span>
	</span>
</button>

<style>
	.list-card {
		display: flex;
		align-items: flex-start;
		gap: var(--space-md);
		width: 100%;
		padding: var(--space-sm);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		background: var(--color-surface);
		color: var(--color-text);
		text-align: start;
		cursor: pointer;
	}
	.list-card:hover {
		border-color: var(--color-primary);
	}
	.list-card:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}
	.thumb {
		flex: none;
		width: 4.75rem;
		height: 4.75rem;
		overflow: hidden;
		border-radius: var(--radius-md);
		background: var(--color-bg-tertiary);
	}
	.body {
		display: flex;
		flex-direction: column;
		gap: var(--space-2xs);
		min-width: 0;
	}
	.name {
		font-weight: 700;
		overflow-wrap: anywhere;
	}
	.official {
		display: flex;
		align-items: center;
		gap: var(--space-xs);
		color: var(--color-primary);
		font-size: 0.85rem;
		font-weight: 600;
	}
	.official .material-symbols {
		font-size: 1rem;
	}
	.meta {
		color: var(--color-text-secondary);
		font-size: 0.85rem;
	}
</style>
