import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/app_constants.dart';
import '../../data/appliance_providers.dart';
import '../../data/nilm_providers.dart';
import '../../domain/nilm/nilm_engine.dart';

class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insights = ref.watch(nilmInsightsProvider);
    return insights.when(
      loading: () => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text(AppConstants.insightsLoading),
          ],
        ),
      ),
      error: (error, stackTrace) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${AppConstants.insightsError}: $error'),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => ref.invalidate(nilmInsightsProvider),
              child: const Text(AppConstants.insightsRetryLabel),
            ),
          ],
        ),
      ),
      data: (snapshot) => _InsightsContent(
        snapshot: snapshot,
        onEditOverride: (appliance) =>
            _editManualWattage(context, ref, appliance),
      ),
    );
  }

  Future<void> _editManualWattage(
    BuildContext context,
    WidgetRef ref,
    NilmApplianceEstimate estimate,
  ) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => _ManualWattageDialog(estimate: estimate),
    );
    if (result == null || !context.mounted) {
      return;
    }

    try {
      final appliances = await ref.read(appliancesProvider.future);
      final appliance = appliances.firstWhere(
        (item) => item.relay == estimate.relay,
      );
      final wattage = result.isEmpty ? null : double.parse(result);
      await ref
          .read(applianceRepositoryProvider)
          .save(
            appliance.copyWith(
              manualWattage: wattage,
              clearManualWattage: wattage == null,
            ),
          );
      ref
        ..invalidate(appliancesProvider)
        ..invalidate(nilmInsightsProvider);
    } on Exception catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${AppConstants.insightsOverrideSaveError}: $error'),
          ),
        );
      }
    }
  }
}

class _ManualWattageDialog extends StatefulWidget {
  const _ManualWattageDialog({required this.estimate});

  final NilmApplianceEstimate estimate;

  @override
  State<_ManualWattageDialog> createState() => _ManualWattageDialogState();
}

class _ManualWattageDialogState extends State<_ManualWattageDialog> {
  late final TextEditingController _controller;
  String? _validationMessage;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.estimate.manualWattage?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final estimate = widget.estimate;
    return AlertDialog(
      title: Text('${AppConstants.insightsOverrideLabel}: ${estimate.name}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(AppConstants.insightsOverrideHint),
          const SizedBox(height: 8),
          Text(
            estimate.learnedWattage == null
                ? AppConstants.insightsNoWattage
                : '${AppConstants.insightsLearnedEstimateLabel}: '
                      '${estimate.learnedWattage!.toStringAsFixed(1)} W',
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('nilm-manual-wattage-field'),
            controller: _controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: AppConstants.insightsWattageInputLabel,
              border: OutlineInputBorder(),
            ),
          ),
          if (_validationMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              _validationMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        if (estimate.manualWattage != null)
          TextButton(
            onPressed: () => Navigator.of(context).pop(''),
            child: const Text(AppConstants.insightsClearOverride),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(AppConstants.insightsCancelLabel),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text(AppConstants.insightsSaveLabel),
        ),
      ],
    );
  }

  void _save() {
    final value = _controller.text.trim();
    if (value.isNotEmpty) {
      final wattage = double.tryParse(value);
      if (wattage == null || !wattage.isFinite || wattage < 0) {
        setState(() {
          _validationMessage = AppConstants.insightsOverrideInvalid;
        });
        return;
      }
    }
    Navigator.of(context).pop(value);
  }
}

class _InsightsContent extends StatelessWidget {
  const _InsightsContent({
    required this.snapshot,
    required this.onEditOverride,
  });

  final NilmInsightSnapshot snapshot;
  final ValueChanged<NilmApplianceEstimate> onEditOverride;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          AppConstants.insightsTitle,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text(AppConstants.insightsLearningHelp),
        const SizedBox(height: 16),
        _EnergyTotalsCard(snapshot: snapshot),
        const SizedBox(height: 16),
        for (final appliance in snapshot.appliances) ...[
          _ApplianceEstimateCard(
            appliance: appliance,
            onEditOverride: () => onEditOverride(appliance),
          ),
          const SizedBox(height: 8),
        ],
        _OtherEnergyCard(snapshot: snapshot),
      ],
    );
  }
}

class _EnergyTotalsCard extends StatelessWidget {
  const _EnergyTotalsCard({required this.snapshot});

  final NilmInsightSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppConstants.insightsMeasuredEnergy,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text('${snapshot.measuredTotalKwh.toStringAsFixed(3)} kWh'),
            const SizedBox(height: 12),
            Text(AppConstants.insightsEstimatedEnergy),
            Text(
              '${snapshot.estimatedApplianceKwh.toStringAsFixed(3)} kWh '
              '${AppConstants.insightsFromRelays}',
            ),
            if (snapshot.measuredTotalKwh == 0) ...[
              const SizedBox(height: 8),
              const Text(AppConstants.insightsNoMeterEnergy),
            ],
            if (snapshot.modelExcessKwh > 0) ...[
              const SizedBox(height: 8),
              Text(
                '${AppConstants.insightsModelExcess} '
                '${AppConstants.insightsMismatchLabel}: '
                '${snapshot.modelExcessKwh.toStringAsFixed(3)} kWh.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ApplianceEstimateCard extends StatelessWidget {
  const _ApplianceEstimateCard({
    required this.appliance,
    required this.onEditOverride,
  });

  final NilmApplianceEstimate appliance;
  final VoidCallback onEditOverride;

  @override
  Widget build(BuildContext context) {
    final confidenceLabel = appliance.isLowConfidenceLoad
        ? AppConstants.insightsLowConfidenceLabel
        : appliance.manualWattage != null
        ? AppConstants.insightsManualConfidenceLabel
        : switch (appliance.confidence) {
            >= 0.7 => AppConstants.insightsHighConfidenceLabel,
            >= 0.4 => AppConstants.insightsMediumConfidenceLabel,
            _ => AppConstants.insightsLowConfidenceShortLabel,
          };
    final wattageText = appliance.effectiveWattage == null
        ? AppConstants.insightsNoWattage
        : '${appliance.effectiveWattage!.toStringAsFixed(1)} W'
              '${appliance.manualWattage == null ? '' : ' · ${AppConstants.insightsManualSuffix}'}';
    final progress = (appliance.sharePercent / 100).clamp(0.0, 1.0);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    appliance.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text('${appliance.sharePercent.toStringAsFixed(1)}%'),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: progress.toDouble()),
            const SizedBox(height: 8),
            Text('${AppConstants.insightsTypicalPower}: $wattageText'),
            Text(
              '${appliance.energyKwh.toStringAsFixed(3)} '
              '${AppConstants.insightsTodaySuffix} '
              '· ${appliance.sampleCount} ${AppConstants.insightsLearningSamples}',
            ),
            Text(
              '${AppConstants.insightsConfidence}: $confidenceLabel'
              '${appliance.spreadWatts == null ? '' : ' · ${AppConstants.insightsSpread} '
                        '${appliance.spreadWatts!.toStringAsFixed(1)} W'}',
            ),
            if (appliance.isLowConfidenceLoad) ...[
              const SizedBox(height: 4),
              const Text(AppConstants.insightsLowConfidenceReason),
            ],
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: Key('nilm-override-${appliance.relay}'),
                onPressed: onEditOverride,
                icon: const Icon(Icons.edit_outlined),
                label: Text(AppConstants.insightsEditOverride),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OtherEnergyCard extends StatelessWidget {
  const _OtherEnergyCard({required this.snapshot});

  final NilmInsightSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final progress = (snapshot.otherSharePercent / 100).clamp(0.0, 1.0);
    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    AppConstants.insightsOtherUnknown,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text('${snapshot.otherSharePercent.toStringAsFixed(1)}%'),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: progress.toDouble()),
            const SizedBox(height: 8),
            Text(
              '${snapshot.otherKwh.toStringAsFixed(3)} '
              '${AppConstants.insightsTodaySuffix}',
            ),
            const SizedBox(height: 4),
            const Text(AppConstants.insightsOtherDescription),
          ],
        ),
      ),
    );
  }
}
