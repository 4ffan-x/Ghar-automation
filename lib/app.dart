import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'core/app_constants.dart';
import 'data/monitor_providers.dart';
import 'data/mqtt_providers.dart';
import 'data/nilm_providers.dart';
import 'data/repositories/nilm_repository.dart';
import 'data/repositories/power_history_repository.dart';
import 'domain/models/mqtt_readings.dart';
import 'data/mqtt_status_chip.dart';
import 'features/control/control_screen.dart';
import 'features/insights/insights_screen.dart';
import 'features/monitor/monitor_screen.dart';
import 'features/settings/settings_screen.dart';

class GharApp extends ConsumerWidget {
  const GharApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

class _NavigationShell extends StatefulWidget {
  const _NavigationShell();

  @override
  State<_NavigationShell> createState() => _NavigationShellState();
}

class _NavigationShellState extends State<_NavigationShell> {
  int _selectedIndex = 0;

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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppConstants.tabLabels[_selectedIndex]),
        actions: const [MqttStatusChip(), SizedBox(width: 8)],
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
}
