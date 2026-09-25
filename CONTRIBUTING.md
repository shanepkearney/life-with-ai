# Contributing a pattern

Found a seed worth showing off, or want to add a classic from Life's history? Add it to the
**Community** tab. Once your pull request is merged, it's in the app, with credit to its discoverer
and to your GitHub.

Every community pattern is a standard [RLE](https://conwaylife.com/wiki/Run_Length_Encoded) file,
the format Golly, LifeViewer and the LifeWiki use, so each one opens unchanged in those tools. Every
card in the app has a **Download .rle** button that saves the file itself.

## The quick way: from the app

1. Heart the seed so it's in **Favorites**. You can heart one of Claude's designs, a board you drew,
   or a moment you caught with the heart in the control bar.
2. On its card in Favorites, press the 🌐 **Submit to the community** button.
3. GitHub opens a new `.rle` file in `community/seeds/` with the entry filled in. Replace
   `your-github-username` (it appears twice) with yours, check the name and description, and press
   **Propose changes**. If you don't have write access, GitHub forks the repo and opens the pull request
   for you. Any commit message is fine: the release notes credit your pattern by its name and your
   username either way.

Very large seeds don't fit in GitHub's link. For those, the app copies the file to your clipboard
instead, so you paste it into the new file.

## By hand

Add one file to `community/seeds/`, named after the pattern: `Gosper glider gun` goes in
`gosper-glider-gun.rle`. The details ride in RLE's comment lines:

```
#N Gosper glider gun
#O Bill Gosper, 1970
#C The first gun ever found, and the answer to Conway's question of
#C whether a pattern can grow forever: it fires a glider every 30
#C generations, a stream that never stops.
#C Source: https://conwaylife.com/wiki/Gosper_glider_gun
#C Added: 2026-09-25 by @your-github-username
x = 36, y = 9, rule = B3/S23
24bo$22bobo$12b2o6b2o12b2o$11bo3bo4b2o12b2o$2o8bo5bo3b2o$2o8bo3bob2o4b
obo$10bo5bo7bo$11bo3bo$12b2o!
```

| Line | Rules |
|---|---|
| `#N` | Required, once, up to 40 characters, not already taken. The file name must match it. |
| `#O` | Required, once: who found or discovered it, up to 80 characters. For your own seed, your GitHub username; for a classic, its discoverer and year. |
| `#C …` | Required: what happens as it plays, up to 400 characters in all. Use as many `#C` lines as you like. |
| `#C Prompt: …` | Optional, up to 160 characters: the prompt, when the assistant made it. |
| `#C Source: https://…` | Required when `#O` isn't you: where the pattern comes from. |
| `#C License: …` | When the source's license isn't CC BY 4.0, name it, e.g. `GFDL 1.2, from the LifeWiki`. |
| `#C Plays on: endless plane` | For a pattern that sends things out (a gun's gliders, Primer's spaceships): on a wrap-around board they'd come back and wreck it, so it plays on HashLife's endless plane instead. |
| `#C Added: YYYY-MM-DD by @you` | Required, once: the date and your GitHub username. The tab lists the newest first. |
| `#CXRLE Pos=x,y` | Optional, with a torus in the rule (`rule = B3/S23:T512,384`): the exact board a seed made in the app was on, and where it sat. The Submit button writes both. |
| the pattern | Conway's rule (`B3/S23`), LifeHistory or LifeSuper, with at least one live cell. |

A pattern without a board of its own plays centered on the app's medium board, or the smallest larger
one that holds it. One too big for any board (like a Turing machine) plays on HashLife's endless plane.
Everything is shown as plain text: the app never renders it as HTML or Markdown.

## Licensing

- **Your own seeds:** by submitting one, you license it under
  [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) and confirm it's yours to license. Anyone may then
  share and reuse it, crediting you (see [community/LICENSE.md](community/LICENSE.md)).
- **Patterns found by others:** add only patterns from sources that share them openly, with the discoverer in
  `#O` and the page in `#C Source:`. The [LifeWiki](https://conwaylife.com/wiki/)'s content is under the
  GNU Free Documentation License 1.2, so a pattern file taken from it carries `#C License: GFDL 1.2, from the LifeWiki`.
  The pattern stays credited to its discoverer, not to you; the description you write is licensed under
  CC BY 4.0. If a pattern's page or file says it may not be shared, or says nothing about sharing, leave it out.
- **Code:** the project's code is under the [MIT license](LICENSE), and code contributions are accepted under it
  too: by submitting a code change, you license it under the MIT license.

## The check

Every pull request runs `test/community_seeds_test.dart`, which checks the rules above. If it fails,
the message names the file and the problem. To run it before you push:

```bash
flutter test test/community_seeds_test.dart
```

Patterns are reviewed before merging. Keep names and descriptions friendly: this is a gallery that
anyone might open.
