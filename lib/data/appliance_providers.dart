import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/appliance.dart';
import 'repositories/appliance_repository.dart';

final applianceRepositoryProvider = Provider<ApplianceRepository>((ref) {
  throw StateError('ApplianceRepository must be provided at the app root.');
});

final appliancesProvider = FutureProvider<List<Appliance>>((ref) {
  return ref.watch(applianceRepositoryProvider).loadAll();
});
