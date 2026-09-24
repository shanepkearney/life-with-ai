import 'package:flutter_test/flutter_test.dart';

import '../../tool/release_notes.dart';

void main() {
  ReleasedCommit c(String message, {int? pr, String sha = 'abc1234'}) => (sha: sha, message: message, pr: pr);

  test('groups commits by kind, oldest first, linking the pull request or the commit', () {
    final notes = releaseNotes(
      version: '1.3.0',
      previousTag: 'v1.2.0',
      // Newest first, as git log lists them.
      commits: [
        c('Merge pull request #7 from a/b'),
        c('docs: update the README', pr: 7),
        c('fix: broken links', pr: 7),
        c('feat(ui): community tab', pr: 6),
        c('feat: screenshots', sha: 'def5678'),
      ],
    );
    expect(notes, contains('## Features\n\n- Screenshots (def5678)\n- Community tab (#6)\n'));
    expect(notes, contains('## Fixes\n\n- Broken links (#7)\n'));
    expect(notes, contains('## Docs and maintenance\n\n- Update the README (#7)\n'));
    expect(notes, isNot(contains('Merge pull request')));
    expect(notes, contains('https://github.com/shanepkearney/life-with-ai/compare/v1.2.0...v1.3.0'));
    expect(notes, contains('https://shanepkearney.github.io/life-with-ai/'));
  });

  test("links what the release built, pinned to its own version", () {
    final notes = releaseNotes(version: '1.3.0', previousTag: 'v1.2.0', commits: [c('feat: x')]);
    expect(notes, contains('## Downloads'));
    expect(notes, contains('https://github.com/shanepkearney/life-with-ai/releases/download/v1.3.0/Life-with-AI.dmg'));
    expect(notes, isNot(contains('/latest/')));
    expect(notes.indexOf('## Downloads'), lessThan(notes.indexOf('## Features')));
  });

  test('breaking changes come first', () {
    final notes = releaseNotes(
      version: '2.0.0',
      previousTag: 'v1.3.0',
      commits: [c('feat: nice'), c('feat!: new link format'), c('fix: x\n\nBREAKING CHANGE: y')],
    );
    expect(notes.indexOf('## Breaking changes'), lessThan(notes.indexOf('## Features')));
    expect(notes, contains('- New link format'));
    expect(notes, contains('- X'));
  });

  test('a hand-written intro goes on top; the first release links the whole history', () {
    final notes = releaseNotes(
      version: '1.0.0',
      previousTag: null,
      commits: [c('feat: everything')],
      intro: '## Welcome to the unknown.\n',
    );
    expect(notes, startsWith('## Welcome to the unknown.\n\n## Downloads'));
    expect(notes, contains('https://github.com/shanepkearney/life-with-ai/commits/v1.0.0'));
  });

  test('squash suffixes and unprefixed subjects read cleanly', () {
    final notes = releaseNotes(version: '1.0.1', previousTag: 'v1.0.0', commits: [c('fix: tidy (#12)', pr: 12), c('Tweak the glow')]);
    expect(notes, contains('- Tidy (#12)'));
    expect(notes, isNot(contains('(#12) (#12)')));
    expect(notes, contains('## Docs and maintenance\n\n- Tweak the glow'));
  });

  test('says so when there is nothing new', () {
    expect(releaseNotes(version: '1.0.0', previousTag: 'v1.0.0', commits: []), contains('No changes since v1.0.0.'));
  });
}
