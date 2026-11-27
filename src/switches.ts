/** Shared switch catalog — keep in sync with macos/Kleam/SwitchCatalog.swift. */

export type SwitchPack = {
  slug: string;
  name: string;
  feel: string;
  /** CSS linear-gradient stops [top, bottom]. */
  gradient: readonly [string, string];
  isNew?: boolean;
};

export const SWITCHES: readonly SwitchPack[] = [
  {
    slug: "cardboard",
    name: "Cardboard",
    feel: "Dry mid tap · short decay",
    gradient: ["#b88c5c", "#7a5733"],
  },
  {
    slug: "cream",
    name: "Cream",
    feel: "Deep thock · heavy body · soft crack",
    gradient: ["#f5ebd1", "#d1bd94"],
  },
  {
    slug: "crystal-purple",
    name: "Crystal Purple",
    feel: "Glassy mid-high · bright short body",
    gradient: ["#b885eb", "#6b38ad"],
  },
  {
    slug: "japanese-black",
    name: "Japanese Black",
    feel: "Sharp click · thin body",
    gradient: ["#47474d", "#141417"],
  },
  {
    slug: "milky-yellow",
    name: "Milky Yellow",
    feel: "Smooth linear · mid thock",
    gradient: ["#fae673", "#e0b82e"],
  },
  {
    slug: "oreo",
    name: "Oreo",
    feel: "Tactile mid bump · balanced",
    gradient: ["#f2f2f0", "#242426"],
  },
  {
    slug: "super-red",
    name: "Super Red",
    feel: "Linear · deep thock",
    gradient: ["#fa7085", "#e01c47"],
    isNew: true,
  },
] as const;

export const DEFAULT_SWITCH_SLUG = "super-red";

export function switchBySlug(slug: string): SwitchPack {
  return SWITCHES.find((pack) => pack.slug === slug) ?? SWITCHES[SWITCHES.length - 1]!;
}
