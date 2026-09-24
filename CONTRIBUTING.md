# Contributing a seed

Found a seed worth showing off? Add it to the **Community** tab. Once your pull request is merged,
the seed is in the app, with credit to your GitHub.

## The quick way: from the app

1. Heart the seed so it's in **Favorites**. You can heart one of Claude's designs, a board you drew,
   or a moment you caught with the heart in the control bar.
2. On its card in Favorites, press the 🌐 **Submit to the community** button.
3. GitHub opens a new file in `community/seeds/` with the entry filled in. Put your GitHub username
   in `author`, check the `name` and `description`, and press **Propose changes**. If you don't have
   write access, GitHub forks the repo and opens the pull request for you. Any commit message is fine:
   the release notes credit your seed by its name and your username either way.

Very long seeds don't fit in GitHub's link. For those, the app copies the entry to your clipboard
instead, so you paste it into the new file.

## By hand

Add one file to `community/seeds/`, named after the seed: `Oscillator Garden` goes in
`oscillator-garden.json`.

```json
{
  "name": "Oscillator Garden",
  "author": "your-github-username",
  "added": "2026-09-24",
  "description": "Four R-pentominoes in 4-fold rotational symmetry. They erupt, swirl into a pinwheel, and leave a wide garden of blinkers and still lifes behind.",
  "prompt": "A symmetric bloom that slowly settles into a garden of oscillators",
  "link": "https://shanepkearney.github.io/life-with-ai/#seed=1_512x384_216_152_b2o78bo-2o78b3o-bo80bo78-o80bo-3o78b2o-bo78b2o"
}
```

| Field | Rules |
|---|---|
| `name` | Required, up to 40 characters, not already taken. The file name must match it. |
| `author` | Required, your GitHub username. It's shown as `by @you` and links to your profile. |
| `added` | Required, the date as `YYYY-MM-DD`. The tab lists the newest first. |
| `description` | Required, up to 400 characters: what happens as it plays. |
| `prompt` | Optional, up to 160 characters: the prompt the seed was made from, if the assistant made it. |
| `link` | Required: a share link from the app (the 🔗 button). The seed must not be empty or already listed. |

Everything is plain, single-line text. The app never renders it as HTML or Markdown.

## Licensing

- **Seeds:** by submitting a seed, you license it under
  [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) and confirm it's yours to license. Anyone may then
  share and reuse it, crediting you as its author (see [community/LICENSE.md](community/LICENSE.md)).
- **Code:** the rest of the project is all rights reserved ([LICENSE](LICENSE)). By submitting a code change, you
  agree that Shane Kearney may use, modify and distribute it as part of this project.

## The check

Every pull request runs `test/community_seeds_test.dart`, which checks the rules above. If it fails,
the message names the file and the problem. To run it before you push:

```bash
flutter test test/community_seeds_test.dart
```

Seeds are reviewed before merging. Keep names and descriptions friendly: this is a gallery that
anyone might open.
