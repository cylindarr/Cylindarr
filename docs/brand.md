# Brand

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="images/cylindarr-lockup-dark.svg">
  <img src="images/cylindarr-lockup-light.svg" alt="Cylindarr" width="280">
</picture>

**The mark is a tube seen end on, with a light at the far end.** A solid disc is the tube's face, and the bore is drilled through it off-centre, so one side of the wall is thick and the other thin, which is what makes it read as depth rather than a ring. In the bore, an amber play triangle is the light at the end of the tube. The name is "tube" said another way (a tube is a cylinder, and the arr suffix puts it beside Sonarr and Radarr).

The wordmark is Rubik SemiBold, outlined, in indigo with the "arr" in amber.

## Colours

| | Light pages | Dark pages |
|---|---|---|
| Tube (indigo) | `#3d4a8f` | `#9ea9ec` |
| Light (amber) | `#f0b04a` | `#f5c46e` |
| Amber in text | `#e39a26` | `#f5c46e` |
| Dark tiles | `#161a33` | |

Amber belongs to the mark and the wordmark only; it is never a state in the interface. Nothing in the brand is red, and the mark is never a play triangle in a rounded rectangle, so it is not mistaken for YouTube's.

## The pages

Dark by default, light on request (the button at the right of the header, remembered per browser). Every video state has a colour, a glyph, and words, so none depends on colour alone, and every text colour passes WCAG AA on its background:

| State | Light | Dark |
|---|---|---|
| In the library ● | `#2f6f45` | `#7cc79a` |
| Wanted ○ | `#3d4a8f` | `#9ea9ec` |
| Waiting to retry ◷ | `#5b6478` | `#a7afc2` |
| Needs you ! | `#c0263b` | `#ff8f9b` |
| Skipped – | `#6b7079` | `#8e94a0` |
| Warnings | `#a4500c` | `#f39c5a` |

They are the custom properties at the top of `Public/cylindarr.css`. The icons in `Public/` and the logos in `docs/images/` are drawn from the same geometry.
