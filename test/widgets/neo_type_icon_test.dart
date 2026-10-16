import 'package:awalingo/widgets/neo_type_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // These names come from the web Voting Page's approved Lucide icon set.
  const cases = {
    'POPULAR': 'star',
    'adoptive': 'recycle',
    'FUNCTIONAL': 'wrench',
    'root': 'tree-palm',
    'CREATIVE': 'brain',
    'non-conforming': 'brain',
    'unknown': 'circle',
  };

  for (final brightness in Brightness.values) {
    for (final entry in cases.entries) {
      testWidgets('${entry.key} renders the approved icon in $brightness', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: Scaffold(body: NeoTypeIcon(type: entry.key)),
          ),
        );
        await tester.pumpAndSettle();

        final picture = tester.widget<SvgPicture>(find.byType(SvgPicture));
        final loader = picture.bytesLoader as SvgAssetLoader;
        expect(loader.assetName, 'assets/neo-types/${entry.value}.svg');
        expect(
          picture.colorFilter,
          ColorFilter.mode(
            brightness == Brightness.dark
                ? const Color(0xFFA3A3A3)
                : const Color(0xFF525252),
            BlendMode.srcIn,
          ),
        );
        expect(tester.getSize(find.byType(SvgPicture)), const Size(24, 24));
        expect(tester.takeException(), isNull);
      });
    }
  }
}
