import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/app_config.dart';
import '../../services/account_deletion_service.dart';
import '../../services/auth_provider.dart';

class AccountDeletionScreen extends StatefulWidget {
  const AccountDeletionScreen({super.key, this.submit, this.onAccepted});
  final Future<void> Function()? submit;
  final Future<void> Function()? onAccepted;
  @override
  State<AccountDeletionScreen> createState() => _AccountDeletionScreenState();
}

class _AccountDeletionScreenState extends State<AccountDeletionScreen> {
  final _confirmation = TextEditingController();
  AccountDeletionService? _service;
  bool _busy = false;
  bool _accepted = false;
  bool _needsSignIn = false;
  String? _error;
  String? _ownerId;
  bool _ownerInitialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.submit != null) return;
    final owner = AuthProvider.of(context).user?.id;
    if (_ownerInitialized && owner != _ownerId && !_accepted) {
      _confirmation.clear();
      _error = 'Your account changed. Review these details and confirm again.';
    }
    _ownerId = owner;
    _ownerInitialized = true;
  }

  Future<void> _request() async {
    if (_busy || _accepted || _confirmation.text != 'DELETE') return;
    final auth = widget.onAccepted == null ? AuthProvider.of(context) : null;
    final ownerId = auth?.user?.id;
    setState(() {
      _busy = true;
      _error = null;
      _needsSignIn = false;
    });
    try {
      if (widget.submit != null) {
        await widget.submit!();
      } else {
        _service ??= AccountDeletionService(
          origin: AppConfig.current.webBaseUrl,
          accessToken: () =>
              Supabase.instance.client.auth.currentSession?.accessToken,
        );
        await _service!.requestDeletion();
      }
      if (!mounted) return;
      setState(() {
        _accepted = true;
      });
      // Acceptance is durable even if local sign-out encounters a network error.
      try {
        if (widget.onAccepted != null) {
          await widget.onAccepted!();
        } else {
          if (ownerId != null) await auth!.logoutAfterDeletion(ownerId);
        }
      } catch (_) {
        /* The request remains accepted. */
      }
    } on AccountDeletionException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _needsSignIn = error.needsSignIn;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Unable to confirm your request. Please retry.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _confirmation.dispose();
    _service?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_busy && !_accepted,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Delete account'),
          automaticallyImplyLeading: !_busy && !_accepted,
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Icon(
                _accepted
                    ? Icons.check_circle_outline
                    : Icons.person_remove_outlined,
                size: 48,
                color: _accepted ? colors.primary : colors.error,
              ),
              const SizedBox(height: 20),
              if (_accepted) ...[
                Text(
                  'Deletion requested',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Your request has been received. You have been signed out. We aim to complete deletion within 30 days.',
                ),
                const SizedBox(height: 16),
                const Text(
                  'Published words and translations remain without your personal attribution. Limited payment records may be retained for accounting or legal obligations.',
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () => Navigator.of(
                          context,
                        ).pushNamedAndRemoveUntil('/signin', (_) => false),
                  child: const Text('Return to sign in'),
                ),
              ] else ...[
                Text(
                  'Leave Awalingo',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                const Text(
                  'This permanently deletes your account on both the mobile app and website. You will lose your profile, preferences, progress and access to unused Cowries. Deletion does not automatically issue a refund.',
                ),
                const SizedBox(height: 16),
                const Text(
                  'Your private activity, notifications and uploaded recordings will be removed. Published words and translations remain without your personal attribution. Limited payment records may be retained for accounting or legal obligations.',
                ),
                const SizedBox(height: 16),
                const Text(
                  'Type DELETE to confirm your request. Requests are processed within 30 days. After confirmation, the request cannot be cancelled in the app.',
                ),
                const SizedBox(height: 16),
                const Text(
                  'If you cannot sign in or need help, contact privacy@awalingo.com.',
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _confirmation,
                  enabled: !_busy,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'Type DELETE to confirm',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
                if (_error != null) ...[
                  Semantics(
                    liveRegion: true,
                    child: Text(_error!, style: TextStyle(color: colors.error)),
                  ),
                  const SizedBox(height: 16),
                ],
                FilledButton(
                  key: const Key('request-deletion'),
                  style: FilledButton.styleFrom(backgroundColor: colors.error),
                  onPressed: !_busy && _confirmation.text == 'DELETE'
                      ? _request
                      : null,
                  child: Text(
                    _busy
                        ? 'Submitting request…'
                        : 'Permanently delete my account',
                  ),
                ),
                if (_needsSignIn)
                  TextButton(
                    onPressed: () async {
                      await AuthProvider.of(context).logout();
                      if (context.mounted) {
                        Navigator.of(
                          context,
                        ).pushNamedAndRemoveUntil('/signin', (_) => false);
                      }
                    },
                    child: const Text('Sign in to continue'),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
