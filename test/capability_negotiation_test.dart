// aq_sandbox/test/capability_negotiation_test.dart
//
// Тесты для S-01: capability path matching.
// Доказывают что FsWriteCap('/etc') НЕ выдаётся если policy содержит FsWriteCap('/tmp/**').

import 'dart:io';
import 'package:aq_schema/sandbox.dart';
import 'package:aq_schema/tools.dart';
import 'package:test/test.dart';
import 'package:aq_sandbox/aq_sandbox.dart';

void main() {
  group('DefaultCapabilityMatcher', () {
    const matcher = DefaultCapabilityMatcher();

    group('FsWriteCap path matching', () {
      test('DENY: /etc not granted when policy has /tmp/**', () {
        expect(
          matcher.allows(FsWriteCap('/etc/passwd'), FsWriteCap('/tmp/**')),
          isFalse,
        );
      });

      test('ALLOW: /tmp/x granted when policy has /tmp/**', () {
        expect(
          matcher.allows(FsWriteCap('/tmp/myfile.txt'), FsWriteCap('/tmp/**')),
          isTrue,
        );
      });

      test('ALLOW: /tmp/sub/x granted when policy has /tmp/**', () {
        expect(
          matcher.allows(FsWriteCap('/tmp/sub/dir/file'), FsWriteCap('/tmp/**')),
          isTrue,
        );
      });

      test('DENY: /tmp/sub/x NOT granted when policy has /tmp/* (no deep)', () {
        expect(
          matcher.allows(FsWriteCap('/tmp/sub/file'), FsWriteCap('/tmp/*')),
          isFalse,
        );
      });

      test('ALLOW: /tmp/file granted when policy has /tmp/*', () {
        expect(
          matcher.allows(FsWriteCap('/tmp/file.txt'), FsWriteCap('/tmp/*')),
          isTrue,
        );
      });

      test('ALLOW: any path granted when policy has **', () {
        expect(
          matcher.allows(FsWriteCap('/etc/passwd'), FsWriteCap('**')),
          isTrue,
        );
      });

      test('ALLOW: exact match', () {
        expect(
          matcher.allows(FsWriteCap('/work/output.txt'), FsWriteCap('/work/output.txt')),
          isTrue,
        );
      });
    });

    group('NetOutCap host matching', () {
      test('DENY: api.x.com NOT granted when policy has api.y.com', () {
        expect(
          matcher.allows(NetOutCap('api.x.com'), NetOutCap('api.y.com')),
          isFalse,
        );
      });

      test('ALLOW: any host granted when policy has *', () {
        expect(
          matcher.allows(NetOutCap('api.anthropic.com'), NetOutCap('*')),
          isTrue,
        );
      });

      test('ALLOW: subdomain granted when policy has *.example.com', () {
        expect(
          matcher.allows(NetOutCap('api.example.com'), NetOutCap('*.example.com')),
          isTrue,
        );
      });

      test('DENY: other domain NOT granted when policy has *.example.com', () {
        expect(
          matcher.allows(NetOutCap('api.other.com'), NetOutCap('*.example.com')),
          isFalse,
        );
      });
    });

    group('Type mismatch', () {
      test('DENY: FsReadCap does not match NetOutCap', () {
        expect(
          matcher.allows(FsReadCap('/tmp/**'), NetOutCap('*')),
          isFalse,
        );
      });
    });
  });

  group('BaseSandboxHandle._negotiate() integration', () {
    late LocalFsSandboxHandle handle;
    late String tmpDir;

    setUp(() async {
      tmpDir = '/tmp/aq_test_${DateTime.now().millisecondsSinceEpoch}';
      handle = LocalFsSandboxHandle('test-sandbox', tmpDir);
      await Directory(tmpDir).create(recursive: true);
    });

    tearDown(() async {
      try { await Directory(tmpDir).delete(recursive: true); } catch (_) {}
    });

    test('DENY: FsWriteCap(/etc) not granted when policy allows /tmp/**', () async {
      final policy = SandboxPolicy(
        budget: SandboxResourceBudget.defaults(),
        disposal: SandboxDisposalSpec.cleanAlways(),
        allowedCaps: [FsWriteCap('/tmp/**')],
      );

      final (ctx, _) = await handle.createContext(
        requestedCaps: [FsWriteCap('/etc/passwd')],
        policy: policy,
        runId: 'test-run',
      );

      // fs должен быть null — capability не выдана
      expect(ctx.fs, isNull);
    });

    test('ALLOW: FsWriteCap(/tmp/x) granted when policy allows /tmp/**', () async {
      final policy = SandboxPolicy(
        budget: SandboxResourceBudget.defaults(),
        disposal: SandboxDisposalSpec.cleanAlways(),
        allowedCaps: [FsWriteCap('/tmp/**')],
      );

      final (ctx, _) = await handle.createContext(
        requestedCaps: [FsWriteCap('/tmp/myfile')],
        policy: policy,
        runId: 'test-run',
      );

      expect(ctx.fs, isNotNull);
    });

    test('policy сохраняется в RunContext (S-03 support)', () async {
      final policy = SandboxPolicy.development();
      final (ctx, _) = await handle.createContext(
        requestedCaps: [FsWriteCap('**')],
        policy: policy,
        runId: 'test-run',
      );
      expect(ctx.policy, equals(policy));
    });
  });
}
