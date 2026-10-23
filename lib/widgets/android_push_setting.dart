import 'dart:async';
import 'package:flutter/material.dart';
import '../services/android_push_service.dart';

class AndroidPushSetting extends StatelessWidget {
  final AndroidPushService? service;
  const AndroidPushSetting({super.key, this.service});
  @override
  Widget build(BuildContext context) {
    final controller = service ?? AndroidPushScope.maybeOf(context);
    if (controller == null) {
      return const ListTile(
        leading: Icon(Icons.notifications_active_outlined),
        title: Text('Allow Push Notifications'),
        subtitle: Text('Not available on this device yet'),
        trailing: Switch(value: false, onChanged: null),
      );
    }
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final state = controller.state;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: const Icon(Icons.notifications_active_outlined),
              title: const Text('Allow Push Notifications'),
              subtitle: Text(
                !state.supported
                    ? 'Not configured for this device yet'
                    : state.pendingDisable
                    ? 'Off on this device. Account change has not saved yet.'
                    : 'Push preference for your account, including web. Device permission is also required.',
              ),
              trailing: state.busy
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Switch(
                      value: state.enabled,
                      onChanged: state.supported
                          ? (value) => unawaited(controller.setEnabled(value))
                          : null,
                    ),
            ),
            if (state.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  state.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (state.pendingDisable && !state.busy)
              TextButton(
                onPressed: () => unawaited(controller.setEnabled(false)),
                child: const Text('Retry saving off'),
              ),
            if (state.blockedByOs)
              TextButton(
                onPressed: () => unawaited(controller.openSettings()),
                child: const Text('Open Android notification settings'),
              ),
          ],
        );
      },
    );
  }
}
