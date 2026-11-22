import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/app_constants.dart';
import '../../data/monitor_providers.dart';
import '../../data/mqtt_providers.dart';
import '../../domain/models/mqtt_readings.dart';

class MonitorScreen extends ConsumerWidget {
  const MonitorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(mqttServiceProvider);
    final liveReading = ref
        .watch(mqttPowerProvider)
        .maybeWhen(
          data: (reading) => reading,
          orElse: () => service.latestPower,
        );
    final history = ref.watch(recentPowerHistoryProvider);
    final totals = ref.watch(energyTotalsProvider);
    final tariff = ref.watch(energyTariffProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (liveReading == null)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(AppConstants.monitorWaitingForPower),
            ),
          )
        else ...[
          Row(
            children: [
              Expanded(
                child: _ReadingTile(
                  label: 'Total power',
                  value: liveReading.watts.toStringAsFixed(1),
                  unit: 'W',
                  icon: Icons.bolt,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ReadingTile(
                  label: 'Voltage',
                  value: liveReading.voltage.toStringAsFixed(1),
                  unit: 'V',
                  icon: Icons.electrical_services,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _ReadingTile(
                  label: 'Current',
                  value: liveReading.current.toStringAsFixed(2),
                  unit: 'A',
                  icon: Icons.bolt_outlined,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ReadingTile(
                  label: 'Cumulative energy',
                  value: liveReading.kilowattHours.toStringAsFixed(2),
                  unit: 'kWh',
                  icon: Icons.electric_meter_outlined,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 20),
        Text(
          AppConstants.monitorChartTitle,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        history.when(
          loading: () => const SizedBox(
            height: 220,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, stackTrace) => Text(
            '${AppConstants.monitorHistoryError}: $error',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          data: (samples) =>
              _PowerHistoryChart(samples: samples, liveReading: liveReading),
        ),
        const SizedBox(height: 20),
        Text(
          'Energy and estimated bill',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text('Tariff: Rs ${tariff.toStringAsFixed(2)} per kWh'),
        const SizedBox(height: 8),
        totals.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => Text(
            '${AppConstants.monitorEnergyError}: $error',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          data: (summary) => Column(
            children: [
              _EnergySummaryTile(
                label: AppConstants.monitorTodayEnergy,
                energyKwh: summary.todayKwh,
                bill: summary.todayKwh * tariff,
              ),
              const SizedBox(height: 8),
              _EnergySummaryTile(
                label: AppConstants.monitorMonthEnergy,
                energyKwh: summary.monthKwh,
                bill: summary.monthKwh * tariff,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReadingTile extends StatelessWidget {
  const _ReadingTile({
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
  });

  final String label;
  final String value;
  final String unit;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20),
            const SizedBox(height: 8),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(
              '$value $unit',
              style: Theme.of(context).textTheme.titleMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _PowerHistoryChart extends StatelessWidget {
  const _PowerHistoryChart({required this.samples, required this.liveReading});

  final List<PowerReading> samples;
  final PowerReading? liveReading;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final chartReadings = [...samples];
    if (liveReading != null &&
        (chartReadings.isEmpty ||
            chartReadings.last.receivedAt != liveReading!.receivedAt)) {
      chartReadings.add(liveReading!);
    }

    if (chartReadings.isEmpty) {
      return const Card(
        child: SizedBox(
          height: 220,
          child: Center(child: Text(AppConstants.monitorNoHistory)),
        ),
      );
    }

    final spots = chartReadings
        .map((reading) {
          final minutesAgo = now.difference(reading.receivedAt).inSeconds / 60;
          return FlSpot(-minutesAgo, reading.watts);
        })
        .toList(growable: false);
    final maximumWatts = chartReadings.fold<double>(
      0,
      (maximum, reading) => reading.watts > maximum ? reading.watts : maximum,
    );
    final maxY = maximumWatts <= 0 ? 1.0 : maximumWatts * 1.15;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 16, 12),
            child: SizedBox(
              height: 220,
              child: LineChart(
                LineChartData(
                  minX: -30,
                  maxX: 0,
                  minY: 0,
                  maxY: maxY,
                  gridData: const FlGridData(show: true),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 15,
                        getTitlesWidget: (value, meta) {
                          final label = switch (value.toInt()) {
                            -30 => '30m',
                            -15 => '15m',
                            0 => 'Now',
                            _ => '',
                          };
                          return SideTitleWidget(
                            meta: meta,
                            child: Text(label),
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 44,
                        getTitlesWidget: (value, meta) => Text(
                          value.toStringAsFixed(0),
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: Theme.of(context).colorScheme.primary,
                      barWidth: 3,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: Theme.of(context).colorScheme.primary
                            .withValues(alpha: 0.12),
                      ),
                    ),
                  ],
                ),
                duration: const Duration(milliseconds: 250),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Text(
            '${AppConstants.monitorHistoryLabel}: ${samples.length}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _EnergySummaryTile extends StatelessWidget {
  const _EnergySummaryTile({
    required this.label,
    required this.energyKwh,
    required this.bill,
  });

  final String label;
  final double energyKwh;
  final double bill;

  @override
  Widget build(BuildContext context) {
    final energyLabel = label == AppConstants.monitorTodayEnergy
        ? AppConstants.monitorTodayBill
        : AppConstants.monitorMonthBill;
    return Card(
      child: ListTile(
        title: Text(label),
        subtitle: Text('${energyKwh.toStringAsFixed(3)} kWh'),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(energyLabel, style: Theme.of(context).textTheme.labelSmall),
            Text('Rs ${bill.toStringAsFixed(2)}'),
          ],
        ),
      ),
    );
  }
}
