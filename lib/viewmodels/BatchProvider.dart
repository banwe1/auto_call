import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/BatchService.dart';

final batchServiceProvider = Provider<BatchService>((Ref ref) {
  return BatchService();
});

/// 批次列表状态
class BatchController extends StateNotifier<AsyncValue<List<DialBatch>>> {
  BatchController(this._service) : super(const AsyncValue<List<DialBatch>>.loading()) {
    refresh();
  }

  final BatchService _service;

  Future<void> refresh() async {
    try {
      final List<DialBatch> batches = await _service.load();
      state = AsyncValue<List<DialBatch>>.data(batches);
    } catch (e, st) {
      state = AsyncValue<List<DialBatch>>.error(e, st);
    }
  }

  Future<DialBatch> create({required String name, required int total}) async {
    final DialBatch batch = await _service.create(name: name, total: total);
    await refresh();
    return batch;
  }

  Future<void> delete(String id) async {
    await _service.delete(id);
    await refresh();
  }

  Future<void> rename(String id, String name) async {
    await _service.rename(id, name);
    await refresh();
  }

  Future<void> togglePin(String id) async {
    await _service.togglePin(id);
    await refresh();
  }

  Future<void> updateCounters(
    String id, {
    int dialedDelta = 0,
    int connectedDelta = 0,
    int customerDelta = 0,
  }) async {
    await _service.updateCounters(
      id,
      dialedDelta: dialedDelta,
      connectedDelta: connectedDelta,
      customerDelta: customerDelta,
    );
    await refresh();
  }
}

final batchProvider =
    StateNotifierProvider<BatchController, AsyncValue<List<DialBatch>>>(
  (Ref ref) => BatchController(ref.watch(batchServiceProvider)),
);
