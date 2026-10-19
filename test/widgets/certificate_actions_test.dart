import 'dart:async';
import 'package:awalingo/services/certificate_export_service.dart';
import 'package:awalingo/widgets/certificate_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const certificate = CertificateDetails(
  recipientName: 'Ada Learner',
  language: 'Yoruba',
  levelLabel: 'Beginner',
);

class FakeExporter extends CertificateExportService {
  int imageBuilds = 0;
  int pdfBuilds = 0;
  int imageShares = 0;
  int pdfShares = 0;
  bool fail = false;
  bool failShare = false;
  Completer<Uint8List>? pending;
  Completer<void>? pendingShare;
  final shared = <CertificateDetails>[];
  Rect? origin;

  @override
  Future<Uint8List> createPdf(CertificateDetails details) async {
    pdfBuilds++;
    if (fail) throw StateError('private render failure');
    return Uint8List.fromList([1]);
  }

  @override
  Future<Uint8List> createImage(CertificateDetails details) async {
    imageBuilds++;
    if (fail) throw StateError('private render failure');
    return pending == null ? Uint8List.fromList([2]) : pending!.future;
  }

  @override
  Future<void> shareImage(
    CertificateDetails details,
    Uint8List bytes,
    Rect bounds,
  ) async {
    imageShares++;
    if (failShare) throw StateError('private chooser failure');
    shared.add(details);
    origin = bounds;
    if (pendingShare != null) await pendingShare!.future;
  }

  @override
  Future<void> sharePdf(
    CertificateDetails details,
    Uint8List bytes,
    Rect bounds,
  ) async {
    pdfShares++;
    origin = bounds;
  }
}

void main() => certificateActionsTests();

void certificateActionsTests() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeExporter exporter;
  setUp(() => exporter = FakeExporter());
  Future<void> mount(
    WidgetTester tester, {
    CertificateDetails details = certificate,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CertificateActions(certificate: details, exporter: exporter),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('same certificate can be shared twice after the chooser closes', (
    tester,
  ) async {
    await mount(tester);
    for (var i = 1; i <= 2; i++) {
      await tester.tap(find.text('Share Certificate'));
      await tester.pumpAndSettle();
      expect(exporter.imageShares, i);
      expect(exporter.shared.last, certificate);
      expect(exporter.origin!.width, greaterThan(0));
      expect(exporter.origin!.height, greaterThan(0));
      expect(find.text('Share Certificate'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'double tap and PDF action cannot start another export while busy',
    (tester) async {
      exporter.pending = Completer<Uint8List>();
      await mount(tester);
      await tester.tap(find.text('Share Certificate'));
      await tester.tap(find.text('Share Certificate'));
      await tester.pump();
      expect(exporter.imageBuilds, 1);
      final download = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Download Certificate'),
      );
      expect(download.onPressed, isNull);
      exporter.pending!.complete(Uint8List.fromList([2]));
      await tester.pumpAndSettle();
      expect(exporter.imageShares, 1);
      expect(exporter.pdfBuilds, 0);
    },
  );

  testWidgets('chooser cancellation restores actions without success claims', (
    tester,
  ) async {
    exporter.pendingShare = Completer<void>();
    await mount(tester);
    await tester.tap(find.text('Share Certificate'));
    await tester.pump();
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );
    exporter.pendingShare!.complete();
    await tester.pumpAndSettle();
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNotNull,
    );
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets(
    'failed image export can be retried and PDF download still works',
    (tester) async {
      exporter.fail = true;
      await mount(tester);
      await tester.tap(find.text('Share Certificate'));
      await tester.pumpAndSettle();
      expect(
        find.text('Unable to share certificate. Please try again.'),
        findsOneWidget,
      );
      expect(find.textContaining('private'), findsNothing);
      exporter.fail = false;
      await tester.tap(find.text('Share Certificate'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Download Certificate'));
      await tester.pumpAndSettle();
      expect(exporter.imageBuilds, 2);
      expect(exporter.imageShares, 1);
      expect(exporter.pdfBuilds, 1);
      expect(exporter.pdfShares, 1);
    },
  );

  testWidgets(
    'leaving during generation does not open the native share sheet',
    (tester) async {
      exporter.pending = Completer<Uint8List>();
      await mount(tester);
      await tester.tap(find.text('Share Certificate'));
      await tester.pumpWidget(const SizedBox());
      exporter.pending!.complete(Uint8List.fromList([2]));
      await tester.pumpAndSettle();
      expect(exporter.imageShares, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('updated recipient cannot receive an earlier pending image', (
    tester,
  ) async {
    exporter.pending = Completer<Uint8List>();
    await mount(tester);
    await tester.tap(find.text('Share Certificate'));
    await mount(
      tester,
      details: const CertificateDetails(
        recipientName: 'Bola Learner',
        language: 'Igbo',
        levelLabel: 'Advanced',
      ),
    );
    exporter.pending!.complete(Uint8List.fromList([2]));
    await tester.pumpAndSettle();
    expect(exporter.imageShares, 0);
    exporter.pending = null;
    await tester.tap(find.text('Share Certificate'));
    await tester.pumpAndSettle();
    expect(exporter.shared.single.recipientName, 'Bola Learner');
    expect(exporter.shared.single.language, 'Igbo');
  });

  testWidgets('native share failure releases the busy state for retry', (
    tester,
  ) async {
    exporter.failShare = true;
    await mount(tester);
    await tester.tap(find.text('Share Certificate'));
    await tester.pumpAndSettle();
    expect(
      find.text('Unable to share certificate. Please try again.'),
      findsOneWidget,
    );
    exporter.failShare = false;
    await tester.tap(find.text('Share Certificate'));
    await tester.pumpAndSettle();
    expect(exporter.imageShares, 2);
    expect(exporter.shared.single, certificate);
  });

  testWidgets('covered result screen cannot open a late share sheet', (
    tester,
  ) async {
    exporter.pending = Completer<Uint8List>();
    await mount(tester);
    await tester.tap(find.text('Share Certificate'));
    final context = tester.element(find.byType(CertificateActions));
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Another screen')),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    exporter.pending!.complete(Uint8List.fromList([2]));
    await tester.pumpAndSettle();
    expect(exporter.imageShares, 0);
    Navigator.of(tester.element(find.text('Another screen'))).pop();
    await tester.pumpAndSettle();
    exporter.pending = null;
    await tester.tap(find.text('Share Certificate'));
    await tester.pumpAndSettle();
    expect(exporter.imageShares, 1);
  });

  testWidgets('Copy message uses the current language and exact tracker copy', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await mount(tester);
    await tester.tap(find.text('Copy message'));
    await tester.pumpAndSettle();
    expect(
      copied,
      'I have just passed Awalingo Language Quiz for Yoruba. Check out my certificate.',
    );
  });
}
