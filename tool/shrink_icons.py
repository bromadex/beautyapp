"""Shrinks the Tabler icon font in build/web to the icons the app uses.

Flutter's icon tree-shaking keeps all 5,600 Tabler glyphs (about 2 MB). Run this
after `flutter build web` so the web app only downloads the icons it needs.
"""
import glob
import os
import re
import sys

from fontTools import subset
from fontTools.ttLib import TTFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
pkg = glob.glob(os.path.expanduser('~/.pub-cache/hosted/pub.dev/flutter_tabler_icons-*/lib/flutter_tabler_icons.dart'))
if not pkg:
    sys.exit('flutter_tabler_icons source not found in the pub cache')
codes = dict(re.findall(r'static const IconData (\w+) = IconData\((0x[0-9a-f]+)', open(sorted(pkg)[-1]).read()))

used = set()
for path in glob.glob(os.path.join(ROOT, 'lib', '**', '*.dart'), recursive=True):
    used |= set(re.findall(r'TablerIcons\.(\w+)', open(path).read()))
missing = sorted(u for u in used if u not in codes)
if missing:
    sys.exit('Unknown Tabler icons: %s' % ', '.join(missing))

font = os.path.join(ROOT, 'build/web/assets/packages/flutter_tabler_icons/assets/fonts/tabler-icons.ttf')
before = os.path.getsize(font)
opts = subset.Options()
opts.layout_features = []
opts.notdef_outline = True
tt = TTFont(font)
sub = subset.Subsetter(opts)
sub.populate(unicodes=[int(codes[u], 16) for u in used])
sub.subset(tt)
tt.save(font)
print('tabler-icons.ttf: %d icons, %d -> %d bytes' % (len(used), before, os.path.getsize(font)))
