import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/services/firestore_service.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../data/repositories/pos_repository.dart';

// ─── Active Order State ────────────────────────────────────────────────────────

class ActiveOrderState {
  final int? orderId;
  final int? tableNumber;
  final String orderType;
  final List<OrderItem> items;
  final double subtotal;
  final double discountPercent;
  final double discountFixed;
  final double total;
  final bool isLoading;
  final String clientName;
  final String ticketTitle;

  const ActiveOrderState({
    this.orderId,
    this.tableNumber,
    this.orderType = 'surPlace',
    this.items = const [],
    this.subtotal = 0.0,
    this.discountPercent = 0.0,
    this.discountFixed = 0.0,
    this.total = 0.0,
    this.isLoading = false,
    this.clientName = '',
    this.ticketTitle = '',
  });

  int get itemCount => items.fold(0, (s, i) => s + i.quantity);
  bool get hasOrder => orderId != null;

  ActiveOrderState copyWith({
    int? orderId,
    int? tableNumber,
    String? orderType,
    List<OrderItem>? items,
    double? subtotal,
    double? discountPercent,
    double? discountFixed,
    double? total,
    bool? isLoading,
    String? clientName,
    String? ticketTitle,
  }) {
    return ActiveOrderState(
      orderId: orderId ?? this.orderId,
      tableNumber: tableNumber ?? this.tableNumber,
      orderType: orderType ?? this.orderType,
      items: items ?? this.items,
      subtotal: subtotal ?? this.subtotal,
      discountPercent: discountPercent ?? this.discountPercent,
      discountFixed: discountFixed ?? this.discountFixed,
      total: total ?? this.total,
      isLoading: isLoading ?? this.isLoading,
      clientName: clientName ?? this.clientName,
      ticketTitle: ticketTitle ?? this.ticketTitle,
    );
  }

  ActiveOrderState clear() => const ActiveOrderState();
}

// ─── Active Order Notifier ─────────────────────────────────────────────────────

class ActiveOrderNotifier extends StateNotifier<ActiveOrderState> {
  final PosRepository _repo;
  final Ref _ref;

  ActiveOrderNotifier(this._repo, this._ref) : super(const ActiveOrderState());

  /// Open or start an order for a table
  Future<void> startOrder({
    int? tableNumber,
    String orderType = 'surPlace',
  }) async {
    state = state.copyWith(isLoading: true);
    try {
      final orderId = await _repo.createOrder(
        tableNumber: tableNumber,
        orderType: orderType,
      );
      state = ActiveOrderState(
        orderId: orderId,
        tableNumber: tableNumber,
        orderType: orderType,
      );
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> addProduct({
    required int productId,
    required String nameFr,
    required String nameAr,
    required double price,
  }) async {
    if (state.orderId == null) {
      await startOrder(orderType: state.orderType);
    }
    await _repo.addOrIncrementProduct(
      orderId: state.orderId!,
      productId: productId,
      productNameFr: nameFr,
      productNameAr: nameAr,
      unitPrice: price,
    );
    await _refreshItems();
  }

  Future<void> updateQuantity(int itemId, int qty) async {
    if (state.orderId == null) return;
    await _repo.updateItemQuantity(state.orderId!, itemId, qty);
    await _refreshItems();
  }

  Future<void> removeItem(int itemId) async {
    if (state.orderId == null) return;
    await _repo.removeItem(state.orderId!, itemId);
    await _refreshItems();
  }

  Future<void> applyDiscount({
    double percent = 0.0,
    double fixed = 0.0,
  }) async {
    if (state.orderId == null) return;
    await _repo.applyDiscount(
      orderId: state.orderId!,
      discountPercent: percent,
      discountFixed: fixed,
    );
    // Update state BEFORE refreshItems so _refreshItems uses correct values
    state = state.copyWith(discountPercent: percent, discountFixed: fixed);
    await _refreshItems();
  }

  Future<void> changeOrderType(String type) async {
    state = state.copyWith(orderType: type);
    if (state.orderId != null) {
      final db = _ref.read(appDatabaseProvider);
      await (db.update(db.orders)
            ..where((o) => o.id.equals(state.orderId!)))
          .write(OrdersCompanion(orderType: Value(type)));
    }
  }

  Future<void> setClientName(String name) async {
    state = state.copyWith(clientName: name);
    if (state.orderId != null) {
      final db = _ref.read(appDatabaseProvider);
      await (db.update(db.orders)
            ..where((o) => o.id.equals(state.orderId!)))
          .write(OrdersCompanion(
              customerName: Value(name.isEmpty ? null : name)));
    }
  }

  Future<void> setTableNumber(int? tableNumber) async {
    state = ActiveOrderState(
      orderId: state.orderId,
      tableNumber: tableNumber,
      orderType: state.orderType,
      items: state.items,
      subtotal: state.subtotal,
      discountPercent: state.discountPercent,
      discountFixed: state.discountFixed,
      total: state.total,
      isLoading: state.isLoading,
      clientName: state.clientName,
      ticketTitle: state.ticketTitle,
    );
    if (state.orderId != null) {
      final db = _ref.read(appDatabaseProvider);
      await (db.update(db.orders)
            ..where((o) => o.id.equals(state.orderId!)))
          .write(OrdersCompanion(tableNumber: Value(tableNumber)));
    }
  }

  Future<void> setTicketTitle(String title) async {
    state = state.copyWith(ticketTitle: title);
    if (state.orderId != null) {
      final db = _ref.read(appDatabaseProvider);
      await (db.update(db.orders)
            ..where((o) => o.id.equals(state.orderId!)))
          .write(OrdersCompanion(
              notes: Value(title.isEmpty ? null : title)));
    }
  }

  /// Hold the current order (keep it in DB as open, clear active state).
  Future<void> holdOrder() async {
    if (state.orderId == null) return;
    final heldIds = _ref.read(heldOrderIdsProvider);
    if (!heldIds.contains(state.orderId)) {
      _ref.read(heldOrderIdsProvider.notifier).state = [
        ..._ref.read(heldOrderIdsProvider),
        state.orderId!,
      ];
    }
    state = state.clear();
  }

  /// Resume a previously held order.
  void resumeOrder(int orderId) {
    final heldIds = _ref.read(heldOrderIdsProvider);
    _ref.read(heldOrderIdsProvider.notifier).state =
        heldIds.where((id) => id != orderId).toList();
    loadExistingOrder(orderId);
  }

  /// Send the current order to the kitchen (called after payment is taken).
  /// Saves [paymentMethod] then sets status → inProgress so KDS picks it up.
  Future<void> sendToKitchen({required String paymentMethod}) async {
    if (state.orderId == null) return;
    await _repo.recordPaymentAndSend(state.orderId!, paymentMethod);
    state = state.clear();
  }

  Future<void> finalizeOrder({int? tableNumber}) async {
    if (state.orderId == null) return;
    final effectiveTable = tableNumber ?? state.tableNumber;
    if (tableNumber != null) {
      final db = _ref.read(appDatabaseProvider);
      await (db.update(db.orders)
            ..where((o) => o.id.equals(state.orderId!)))
          .write(OrdersCompanion(tableNumber: Value(tableNumber)));
    }
    await _repo.updateOrderStatus(state.orderId!, 'paid');
    if (effectiveTable != null) {
      try {
        await _repo.freeTable(effectiveTable);
      } catch (_) {}
    }
    state = state.clear();
  }

  Future<void> cancelOrder() async {
    if (state.orderId == null) return;
    await _repo.updateOrderStatus(state.orderId!, 'cancelled');
    if (state.tableNumber != null) {
      await _repo.freeTable(state.tableNumber!);
    }
    state = state.clear();
  }

  void loadExistingOrder(int orderId, {int? tableNumber}) {
    state = ActiveOrderState(orderId: orderId, tableNumber: tableNumber);
    _refreshItems();
  }

  void clearOrder() => state = state.clear();

  Future<void> _refreshItems() async {
    if (state.orderId == null) return;
    final db = _ref.read(appDatabaseProvider);
    final items = await _repo.watchOrderItems(state.orderId!).first;
    final subtotal = items.fold(0.0, (s, i) => s + i.lineTotal);
    final discAmt =
        (subtotal * state.discountPercent / 100) + state.discountFixed;
    final total = (subtotal - discAmt).clamp(0.0, double.infinity);

    // Fetch only the text columns we need — avoids reading DateTime columns
    // which may be stored as ISO strings in the existing DB.
    final row = await db.customSelect(
      'SELECT customer_name, notes, order_type FROM orders WHERE id = ?',
      variables: [Variable.withInt(state.orderId!)],
      readsFrom: {db.orders},
    ).getSingleOrNull();

    state = state.copyWith(
      items: items,
      subtotal: subtotal,
      total: total,
      clientName: row?.read<String?>('customer_name') ?? state.clientName,
      ticketTitle: row?.read<String?>('notes') ?? state.ticketTitle,
      orderType: row?.read<String?>('order_type') ?? state.orderType,
    );
  }
}

final activeOrderProvider =
    StateNotifierProvider<ActiveOrderNotifier, ActiveOrderState>((ref) {
  final repo = ref.watch(posRepositoryProvider);
  return ActiveOrderNotifier(repo, ref);
});

// ─── Held Orders ──────────────────────────────────────────────────────────────

/// IDs of orders that have been put "on hold" (En attente).
final heldOrderIdsProvider = StateProvider<List<int>>((ref) => []);

// ─── Server / Waiter Name ─────────────────────────────────────────────────────

class _ServerNameNotifier extends StateNotifier<String> {
  final AppDatabase _db;

  _ServerNameNotifier(this._db) : super('') {
    _load();
  }

  Future<void> _load() async {
    final saved = await _db.getSetting('server_name');
    if (saved != null && saved.isNotEmpty) state = saved;
  }

  Future<void> set(String name) async {
    state = name;
    await _db.setSetting('server_name', name);
  }
}

/// The name of the current server/waiter — persisted across app restarts.
final serverNameProvider =
    StateNotifierProvider<_ServerNameNotifier, String>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return _ServerNameNotifier(db);
});

// ─── Server Names List ────────────────────────────────────────────────────────

class ServerNamesListNotifier extends StateNotifier<List<String>> {
  final AppDatabase _db;

  ServerNamesListNotifier(this._db) : super([]) {
    _load();
  }

  Future<void> _load() async {
    final raw = await _db.getSetting('server_names_list');
    if (raw != null && raw.isNotEmpty) {
      state = raw.split('|').where((s) => s.isNotEmpty).toList();
    }
  }

  Future<void> add(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || state.contains(trimmed)) return;
    state = [...state, trimmed];
    await _db.setSetting('server_names_list', state.join('|'));
  }

  Future<void> remove(String name) async {
    state = state.where((s) => s != name).toList();
    await _db.setSetting('server_names_list', state.join('|'));
  }
}

/// Persisted list of server/waiter names for quick selection in the POS.
final serverNamesListProvider =
    StateNotifierProvider<ServerNamesListNotifier, List<String>>((ref) {
  return ServerNamesListNotifier(ref.watch(appDatabaseProvider));
});

// ─── Tables Stream ─────────────────────────────────────────────────────────────

final tablesStreamProvider = StreamProvider<List<RestaurantTable>>((ref) {
  final repo = ref.watch(posRepositoryProvider);
  return repo.watchTables();
});

// ─── Active Orders Stream (local — used by waiter device) ─────────────────────

final activeOrdersStreamProvider = StreamProvider<List<Order>>((ref) {
  final repo = ref.watch(posRepositoryProvider);
  return repo.watchActiveOrders();
});

// ─── Firestore Active Orders Stream (shared — used by KDS on all devices) ─────

final firestoreActiveOrdersProvider =
    StreamProvider<List<FirestoreOrder>>((ref) {
  return FirestoreService.watchActiveOrders();
});

// ─── Products & Categories ─────────────────────────────────────────────────────

final categoriesProvider = StreamProvider<List<Category>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.watchAllCategories();
});

final selectedCategoryProvider = StateProvider<int?>((ref) => null);

final productsForCategoryProvider =
    StreamProvider.family<List<Product>, int?>((ref, categoryId) {
  final db = ref.watch(appDatabaseProvider);
  if (categoryId == null) {
    return db.select(db.products).watch();
  }
  return db.watchProductsByCategory(categoryId);
});

// ─── Product search ────────────────────────────────────────────────────────────

final productSearchQueryProvider = StateProvider<String>((ref) => '');

// ─── Product Grid Columns ──────────────────────────────────────────────────────

/// Controls the number of columns in the product grid (2–7)
final productGridColumnsProvider = StateProvider<int>((ref) => 4);

final filteredProductsProvider = Provider<AsyncValue<List<Product>>>((ref) {
  final query = ref.watch(productSearchQueryProvider).toLowerCase();
  final categoryId = ref.watch(selectedCategoryProvider);
  final productsAsync = ref.watch(productsForCategoryProvider(categoryId));

  return productsAsync.whenData((products) {
    if (query.isEmpty) return products;
    return products.where((p) {
      return p.nameFr.toLowerCase().contains(query) ||
          p.nameAr.toLowerCase().contains(query);
    }).toList();
  });
});

// ─── Product Prep Time ─────────────────────────────────────────────────────────

/// Maps productId → estimated preparation minutes.
/// Products in a "Boissons" category → 5 min, everything else → 15 min.
final productPrepTimeProvider = FutureProvider<Map<int, int>>((ref) async {
  final db = ref.read(appDatabaseProvider);
  final allProducts = await db.getAllProducts();
  final allCategories = await db.getAllCategories();

  final drinkCatIds = allCategories
      .where((c) =>
          c.nameFr.toLowerCase().contains('boisson') ||
          c.nameAr.contains('مشروب'))
      .map((c) => c.id)
      .toSet();

  return {
    for (final p in allProducts)
      p.id: drinkCatIds.contains(p.categoryId) ? 5 : 15,
  };
});
