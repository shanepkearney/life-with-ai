import 'package:flutter_test/flutter_test.dart';

import '../../tool/next_version.dart';

void main() {
  group('bumpFor', () {
    test('reads the Conventional Commits type', () {
      expect(bumpFor('feat: community tab'), Bump.minor);
      expect(bumpFor('feat(ui): scoped'), Bump.minor);
      expect(bumpFor('fix: broken links'), Bump.patch);
      expect(bumpFor('docs: README'), Bump.patch);
      expect(bumpFor('chore: reorder seeds'), Bump.patch);
      expect(bumpFor('Tidy up without a prefix'), Bump.patch, reason: 'anything shipped is at least a patch');
    });

    test('a ! or a BREAKING CHANGE footer is major', () {
      expect(bumpFor('feat!: new link format'), Bump.major);
      expect(bumpFor('fix(api)!: drop old links'), Bump.major);
      expect(bumpFor('feat: new link format\n\nBREAKING CHANGE: old links stop working'), Bump.major);
      expect(bumpFor('fix: x\n\nBREAKING-CHANGE: y'), Bump.major);
      expect(bumpFor('fix: mentions breaking change in passing'), Bump.patch);
    });

    test('merge commits count for nothing; the commits they merge do', () {
      expect(bumpFor('Merge pull request #4 from shanepkearney/fix/broken-seed-links'), Bump.none);
      expect(bumpFor(''), Bump.none);
    });
  });

  test('a commit that only touches community seeds is recognized, whatever its message', () {
    expect(isCommunitySeedsOnly(['community/seeds/pool-party.json']), isTrue);
    expect(isCommunitySeedsOnly(['community/seeds/a.json', 'community/seeds/b.json']), isTrue);
    expect(isCommunitySeedsOnly(['community/seeds/a.json', 'lib/main.dart']), isFalse, reason: 'code too: its message decides');
    expect(isCommunitySeedsOnly([]), isFalse, reason: 'a merge commit changes nothing itself');
  });

  group('nextVersion', () {
    test('the first release is 1.0.0', () {
      expect(nextVersion(null, ['feat: everything']), (version: '1.0.0', isNew: true));
      expect(nextVersion(null, []), (version: '1.0.0', isNew: true));
    });

    test('the biggest bump since the last tag wins', () {
      expect(nextVersion('v1.2.3', ['fix: a', 'docs: b']), (version: '1.2.4', isNew: true));
      expect(nextVersion('v1.2.3', ['fix: a', 'feat: b', 'Merge pull request #9']), (version: '1.3.0', isNew: true));
      expect(nextVersion('v1.2.3', ['feat: a', 'fix!: b']), (version: '2.0.0', isNew: true));
    });

    test('nothing new since the last tag keeps its version and tags nothing', () {
      expect(nextVersion('v1.2.3', []), (version: '1.2.3', isNew: false));
      expect(nextVersion('v1.2.3', ['Merge pull request #9 from a/b']), (version: '1.2.3', isNew: false));
    });

    test('only release tags are accepted', () {
      expect(() => nextVersion('release-7', ['fix: a']), throwsFormatException);
    });
  });
}
