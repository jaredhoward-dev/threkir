// The colour of a park's nth course line, as the park map draws it and the
// course card's strip repeats it (decisions § 2612). Keyed on the basemap,
// because the line is drawn over tiles. The values are the categorical
// `--kind-1`..`--kind-6` marks of app.css (ui_kit's `ChartPalette.kinds` on
// mobile, whose `parkCourseLineColour` is this function's twin); MapLibre
// paints a literal colour, not a CSS variable, so they are repeated here and
// park_course_colours.test.ts holds them to app.css.

export const PARK_COURSE_LINE_COLOURS = {
	light: ['#032122', '#13345B', '#6C2C68', '#774F05', '#C72F20', '#7E7B8B'],
	dark: ['#DBF8F9', '#CAE0FC', '#E7BCE2', '#E9AC4F', '#ED8B84', '#9794A5'],
} as const;

export function parkCourseLineColour(index: number, darkBasemap: boolean): string {
	const kinds = darkBasemap ? PARK_COURSE_LINE_COLOURS.dark : PARK_COURSE_LINE_COLOURS.light;
	return kinds[((index % kinds.length) + kinds.length) % kinds.length];
}
