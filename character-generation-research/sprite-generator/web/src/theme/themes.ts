export const THEMES = [
  { id: "solarized-dark", label: "Solarized Dark", density: "compact" },
  { id: "dark-slate-pastel", label: "Dark Slate Pastel", density: "compact" },
  { id: "graphite-teal", label: "Graphite Teal", density: "compact" },
  { id: "wayfarer-dark", label: "Wayfarer Dark", density: "comfortable" },
] as const;
export type ThemeId = (typeof THEMES)[number]["id"];
export const THEME_KEY = "sprite-extractor.theme.v1";
export function readTheme(): ThemeId {
  const value = localStorage.getItem(THEME_KEY);
  return THEMES.some((x) => x.id === value)
    ? (value as ThemeId)
    : "solarized-dark";
}
