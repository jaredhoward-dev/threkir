<script lang="ts">
	// A map's own control in Explore (decisions § 2611): compact, about 36 px,
	// and always labelled, because icon-only map actions proved undiscoverable
	// (§ 1954). A link when it opens another map, a button otherwise; `round`
	// draws an icon-only 44 px disc for Search and Filters on the top edge,
	// which carry their name as the accessible label.
	let {
		label,
		icon,
		href,
		onclick,
		pressed,
		round = false,
		count = 0,
		testid,
	}: {
		label: string;
		icon: string;
		href?: string;
		onclick?: () => void;
		pressed?: boolean;
		round?: boolean;
		/// A count badge on a round button, such as the filters that are on.
		count?: number;
		testid?: string;
	} = $props();
</script>

{#if href}
	<a class="map-btn" {href} data-testid={testid}>
		<span class="material-symbols" aria-hidden="true">{icon}</span>
		<span>{label}</span>
	</a>
{:else if round}
	<button type="button" class="round-btn" aria-label={label} title={label} {onclick} data-testid={testid}>
		<span class="material-symbols" aria-hidden="true">{icon}</span>
		{#if count > 0}<span class="count" aria-hidden="true">{count}</span>{/if}
	</button>
{:else}
	<button type="button" class="map-btn" class:on={pressed} aria-pressed={pressed} {onclick} data-testid={testid}>
		<span class="material-symbols" aria-hidden="true">{icon}</span>
		<span>{label}</span>
	</button>
{/if}

<style>
	.map-btn {
		display: inline-flex;
		align-items: center;
		gap: var(--space-xs);
		min-height: 2.25rem;
		padding: var(--space-2xs) var(--space-sm);
		border: 1px solid var(--color-border);
		border-radius: 9999px;
		background: var(--color-surface);
		color: var(--color-text);
		font-size: 0.8rem;
		font-weight: 600;
		text-decoration: none;
		box-shadow: var(--shadow-md);
		cursor: pointer;
	}
	.map-btn .material-symbols {
		font-size: 1.05rem;
	}
	.map-btn.on {
		background: var(--color-primary);
		border-color: var(--color-primary);
		color: var(--color-on-primary, white);
	}
	.round-btn {
		position: relative;
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: var(--tap-target-min);
		height: var(--tap-target-min);
		border: 1px solid var(--color-border);
		border-radius: 50%;
		background: var(--color-surface);
		color: var(--color-text);
		box-shadow: var(--shadow-md);
		cursor: pointer;
	}
	.count {
		position: absolute;
		top: -0.2rem;
		inset-inline-end: -0.2rem;
		min-width: 1.1rem;
		height: 1.1rem;
		padding: 0 0.25rem;
		border-radius: 9999px;
		background: var(--color-primary);
		color: var(--color-on-primary, white);
		font-size: var(--font-size-section-label);
		font-weight: 700;
		line-height: 1.1rem;
	}
	.map-btn:focus-visible,
	.round-btn:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}
</style>
