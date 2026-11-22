import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'core/app_constants.dart';
import 'data/alert_providers.dart';
import 'data/monitor_providers.dart';
import 'data/mqtt_providers.dart';
import 'data/nilm_providers.dart';
import 'data/repositories/alert_repository.dart';
import 'data/repositories/nilm_repository.dart';
import 'data/repositories/power_history_repository.dart';
import 'domain/models/alert_record.dart';
import 'domain/models/mqtt_readings.dart';
import 'data/mqtt_status_chip.dart';
import 'features/alerts/alert_history_screen.dart';
import 'features/control/control_screen.dart';
import 'features/insights/insights_screen.dart';
import 'features/monitor/monitor_screen.dart';
import 'features/settings/settings_screen.dart';

class GharApp extends ConsumerStatefulWidget {
  const GharApp({super.key});

  @override
  ConsumerState<GharApp> createState() => _GharAppState();
}

class _GharAppState extends ConsumerState<GharApp> {
  @override
  void initState() {
    super.initState();
    unawaited(
      ref.read(alertMonitorProvider).start(
        onAlertsChanged: _invalidateAlertProviders,
      ),
    );
  }

  @override
  void dispose() {
    unawaited(ref.read(alertMonitorProvider).dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final historyRepository = ref.watch(powerHistoryRepositoryProvider);
    final nilmRepository = ref.watch(nilmRepositoryProvider);
    ref.listen(mqttPowerProvider, (previous, next) {
      next.whenData((reading) {
        if (reading != null) {
          unawaited(
            _savePowerReading(ref, historyRepository, nilmRepository, reading),
          );
        }
      });
    });
    ref.listen(mqttRelayStatesProvider, (previous, next) {
      next.whenData((states) {
        if (states.isNotEmpty) {
          unawaited(_saveRelayStates(ref, nilmRepository, states));
        }
      });
    });

    return MaterialApp(
      title: AppConstants.appName,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const _NavigationShell(),
    );
  }

  void _invalidateAlertProviders() {
    if (!mounted) {
      return;
    }
    ref
      ..invalidate(alertHistoryProvider)
      ..invalidate(activeGasAlertProvider);
  }

  Future<void> _savePowerReading(
    WidgetRef ref,
    PowerHistoryRepository repository,
    NilmRepository nilmRepository,
    PowerReading reading,
  ) async {
    try {
      final savedSample = await repository.recordReading(reading);
      if (savedSample) {
        ref.invalidate(recentPowerHistoryProvider);
      }
      ref.invalidate(energyTotalsProvider);
    } on Exception catch (error) {
      debugPrint('Could not save incoming power reading: $error');
    }
    try {
      await nilmRepository.recordPowerReading(reading);
      ref.invalidate(nilmInsightsProvider);
    } on Exception catch (error) {
      debugPrint('Could not process NILM power reading: $error');
    }
  }

  Future<void> _saveRelayStates(
    WidgetRef ref,
    NilmRepository repository,
    Map<int, RelayState> states,
  ) async {
    try {
      await repository.recordConfirmedRelayStates(states);
      ref.invalidate(nilmInsightsProvider);
    } on Exception catch (error) {
      debugPrint('Could not process confirmed relay states for NILM: $error');
    }
  }

  ThemeData _buildTheme(Brightness brightness) {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF176B5B),
        brightness: brightness,
      ),
      useMaterial3: true,
    );
  }
}

class _NavigationShell extends ConsumerStatefulWidget {
  const _NavigationShell();

  @override
  ConsumerState<_NavigationShell> createState() => _NavigationShellState();
}

class _NavigationShellState extends ConsumerState<_NavigationShell>
    with WidgetsBindingObserver {
  int _selectedIndex = 0;
  int? _shownGasAlertId;

  static const _screens = [
    ControlScreen(),
    MonitorScreen(),
    InsightsScreen(),
    SettingsScreen(),
  ];

  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.toggle_on_outlined),
      selectedIcon: Icon(Icons.toggle_on),
      label: AppConstants.controlTab,
    ),
    NavigationDestination(
      icon: Icon(Icons.monitor_heart_outlined),
      selectedIcon: Icon(Icons.monitor_heart),
      label: AppConstants.monitorTab,
    ),
    NavigationDestination(
      icon: Icon(Icons.insights_outlined),
      selectedIcon: Icon(Icons.insights),
      label: AppConstants.insightsTab,
    ),
    NavigationDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings),
      label: AppConstants.settingsTab,
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref
        ..invalidate(alertHistoryProvider)
        ..invalidate(activeGasAlertProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeGasAlert = ref
        .watch(activeGasAlertProvider)
        .maybeWhen(data: (alert) => alert, orElse: () => null);
    if (activeGasAlert != null && _shownGasAlertId != activeGasAlert.id) {
      _shownGasAlertId = activeGasAlert.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_showGasAlert(activeGasAlert));
        }
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(AppConstants.tabLabels[_selectedIndex]),
        actions: [
          IconButton(
            tooltip: 'Alert history',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AlertHistoryScreen(),
              ),
            ),
            icon: const Icon(Icons.notifications_active_outlined),
          ),
          const MqttStatusChip(),
          const SizedBox(width: 8),
        ],
      ),
      body: IndexedStack(index: _selectedIndex, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        destinations: _destinations,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
      ),
    );
  }

  Future<void> _showGasAlert(AlertRecord alert) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      useSafeArea: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: Scaffold(
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 76,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      alert.title,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      alert.message,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () => _acknowledgeGasAlert(
                        dialogContext,
                        alert,
                      ),
                      child: const Text('Acknowledge'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (mounted && _shownGasAlertId == alert.id) {
      setState(() => _shownGasAlertId = null);
    }
  }

  Future<void> _acknowledgeGasAlert(
    BuildContext dialogContext,
    AlertRecord alert,
  ) async {
    try {
      await ref.read(alertRepositoryProvider).acknowledge(alert.id);
      await ref.read(alertNotifierProvider).cancelAlert(alert);
      ref
        ..invalidate(alertHistoryProvider)
        ..invalidate(activeGasAlertProvider);
      if (dialogContext.mounted) {
        Navigator.of(dialogContext).pop();
      }
    } on Exception catch (error) {
      if (dialogContext.mounted) {
        ScaffoldMessenger.of(dialogContext).showSnackBar(
          SnackBar(content: Text('Could not acknowledge alert: $error')),
        );
      }
    }
  }
}
