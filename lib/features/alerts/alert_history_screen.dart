import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/alert_providers.dart';
import '../../domain/models/alert_record.dart';

class AlertHistoryScreen extends ConsumerWidget {
  const AlertHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(alertHistoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Alert history')),
      body: history.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Could not load alert history.'),
              TextButton(
                onPressed: () => ref.invalidate(alertHistoryProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (alerts) {
          if (alerts.isEmpty) {
            return const Center(child: Text('No alerts have been recorded.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: alerts.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) => _AlertCard(alert: alerts[index]),
          );
        },
      ),
    );
  }
}

class _AlertCard extends ConsumerWidget {
  const _AlertCard({required this.alert});

  final AlertRecord alert;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final icon = switch (alert.type) {
      AlertType.gasLeak => Icons.warning_amber_rounded,
      AlertType.heavyUse => Icons.timer_outlined,
      AlertType.loadLimit => Icons.bolt,
      AlertType.deviceOffline => Icons.cloud_off_outlined,
    };
    final dateText = DateFormat('EEE, MMM d · h:mm a').format(
      alert.occurredAt.toLocal(),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: alert.type == AlertType.gasLeak
                    ? colorScheme.error
                    : colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    alert.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Icon(
                  alert.isAcknowledged
                      ? Icons.check_circle_outline
                      : Icons.circle_notifications_outlined,
                  semanticLabel: alert.isAcknowledged
                      ? 'Acknowledged'
                      : 'Unacknowledged',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(alert.message),
            const SizedBox(height: 8),
            Text(
              dateText,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (!alert.isAcknowledged) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => _acknowledge(context, ref),
                  child: const Text('Acknowledge'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _acknowledge(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(alertRepositoryProvider).acknowledge(alert.id);
      if (alert.type == AlertType.gasLeak) {
        await ref.read(alertNotifierProvider).cancelAlert(alert);
      }
      ref
        ..invalidate(alertHistoryProvider)
        ..invalidate(activeGasAlertProvider);
    } on Exception catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not acknowledge alert: $error')),
        );
      }
    }
  }
}
