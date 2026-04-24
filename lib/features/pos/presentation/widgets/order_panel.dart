import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:printing/printing.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/l10n/app_strings.dart';
import '../../../../core/printing/pdf_receipt_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/providers/app_providers.dart';
import '../providers/pos_providers.dart';

class OrderPanel extends ConsumerWidget {
  final ScrollController? scrollController;

  const OrderPanel({super.key, this.scrollController});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(appLocaleProvider);
    final order = ref.watch(activeOrderProvider);
    final size = MediaQuery.sizeOf(context);
    // Compact mode in landscape: hide the ticket-title bar and shrink everything
    final isCompact = size.width > size.height;

    return Container(
      color: AppColors.surfaceCard,
      child: Column(
        children: [
          _buildHeader(locale, order, compact: isCompact),
          // Serveur + Client row
          _ServeurClientBar(locale: locale),
          // Ticket title input — hidden in landscape to save vertical space
          if (!isCompact) _TicketTitleBar(locale: locale),
          Expanded(
            child: order.items.isEmpty
                ? _EmptyOrderState(locale: locale)
                : _OrderItemsList(
                    items: order.items,
                    locale: locale,
                    scrollController: scrollController,
                  ),
          ),
          _buildFooter(context, ref, locale, order, compact: isCompact),
        ],
      ),
    );
  }

  Widget _buildHeader(String locale, ActiveOrderState order, {bool compact = false}) {
    return Container(
      padding: EdgeInsets.fromLTRB(12, compact ? 3 : 5, 12, compact ? 3 : 5),
      decoration: const BoxDecoration(
        color: AppColors.surfaceCard,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.receipt_long,
                color: AppColors.accent, size: 18),
          ),
          const Gap(10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.tableNumber != null
                      ? '${AppStrings.t('table_prefix', locale)} ${order.tableNumber}'
                      : AppStrings.t('order', locale),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (order.orderId != null)
                  Text(
                    '#${order.orderId}',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textMuted),
                  ),
              ],
            ),
          ),
          if (order.itemCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${order.itemCount} ${AppStrings.t('items_short', locale)}',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFooter(
    BuildContext context,
    WidgetRef ref,
    String locale,
    ActiveOrderState order, {
    bool compact = false,
  }) {
    if (!order.hasOrder || order.items.isEmpty) return const SizedBox.shrink();

    final hasDiscount = order.discountPercent > 0 || order.discountFixed > 0;
    final discountAmt =
        (order.subtotal * order.discountPercent / 100) + order.discountFixed;

    // Compact (landscape): tighter padding, smaller total font, smaller buttons
    final outerPad = compact ? 8.0 : 14.0;
    final totalFontSize = compact ? 17.0 : 22.0;
    final dividerHeight = compact ? 10.0 : 16.0;
    final afterTotalGap = compact ? 6.0 : 10.0;
    final btnVertPad = compact ? 6.0 : 10.0;
    final encaisserVPad = compact ? 7.0 : 12.0;

    return Container(
      padding: EdgeInsets.all(outerPad),
      decoration: const BoxDecoration(
        color: AppColors.surfaceCard,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TotalRow(
            label: AppStrings.t('subtotal', locale),
            value: CurrencyFormatter.format(order.subtotal, locale: locale),
          ),
          if (hasDiscount) ...[
            const Gap(4),
            _TotalRow(
              label: AppStrings.t('discount', locale),
              value:
                  '- ${CurrencyFormatter.format(discountAmt, locale: locale)}',
              valueColor: AppColors.accentGreen,
            ),
          ],
          Divider(
              color: AppColors.divider,
              height: dividerHeight,
              thickness: 1),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                AppStrings.t('total', locale),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                CurrencyFormatter.format(order.total, locale: locale),
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: totalFontSize,
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
          Gap(afterTotalGap),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _confirmCancel(context, ref, locale),
                  icon: const Icon(Icons.close, size: 15),
                  label: Text(AppStrings.t('cancel', locale),
                      style: const TextStyle(fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.stockCritical,
                    side: const BorderSide(color: AppColors.stockCritical),
                    padding: EdgeInsets.symmetric(vertical: btnVertPad),
                  ),
                ),
              ),
              const Gap(8),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: () => _processPayment(context, ref, locale),
                  icon: const Icon(Icons.payments_outlined, size: 18),
                  label: Text(
                    AppStrings.t('pay', locale),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accentGreen,
                    padding: EdgeInsets.symmetric(vertical: encaisserVPad),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _confirmCancel(BuildContext context, WidgetRef ref, String locale) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          AppStrings.t('cancel_order_panel_title', locale),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        content: Text(
          AppStrings.t('cancel_order_panel_body', locale),
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AppStrings.t('no', locale))),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(activeOrderProvider.notifier).cancelOrder();
              Navigator.of(context).popUntil((r) => r.isFirst);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.stockCritical),
            child: Text(AppStrings.t('yes_cancel', locale)),
          ),
        ],
      ),
    );
  }

  void _processPayment(BuildContext context, WidgetRef ref, String locale) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ReceiptPreviewDialog(locale: locale),
    );
  }
}

// ─── Serveur + Client Bar ─────────────────────────────────────────────────────

class _ServeurClientBar extends ConsumerStatefulWidget {
  final String locale;
  const _ServeurClientBar({required this.locale});

  @override
  ConsumerState<_ServeurClientBar> createState() => _ServeurClientBarState();
}

class _ServeurClientBarState extends ConsumerState<_ServeurClientBar> {
  late TextEditingController _serveurCtrl;
  late TextEditingController _clientCtrl;

  @override
  void initState() {
    super.initState();
    _serveurCtrl =
        TextEditingController(text: ref.read(serverNameProvider));
    _clientCtrl =
        TextEditingController(text: ref.read(activeOrderProvider).clientName);
  }

  @override
  void dispose() {
    _serveurCtrl.dispose();
    _clientCtrl.dispose();
    super.dispose();
  }

  // Sync controllers when order changes (e.g. order is resumed/loaded)
  @override
  void didUpdateWidget(covariant _ServeurClientBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final clientName = ref.read(activeOrderProvider).clientName;
    if (_clientCtrl.text != clientName) {
      _clientCtrl.text = clientName;
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = widget.locale;
    // Sync server name controller when it loads from DB
    ref.listen(serverNameProvider, (prev, next) {
      if (_serveurCtrl.text != next) {
        _serveurCtrl.text = next;
        _serveurCtrl.selection =
            TextSelection.collapsed(offset: next.length);
      }
    });
    // Watch to rebuild when order changes
    ref.listen(activeOrderProvider, (prev, next) {
      if (next.clientName != _clientCtrl.text) {
        _clientCtrl.text = next.clientName;
      }
    });

    final isCompact = MediaQuery.sizeOf(context).width > MediaQuery.sizeOf(context).height;
    final savedNames = ref.watch(serverNamesListProvider);

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surfaceCard,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: isCompact ? 1 : 3),
      child: Row(
        children: [
          // Serveur field + picker button
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: _LabeledField(
                    icon: Icons.person_outline,
                    label: AppStrings.t('server', locale),
                    controller: _serveurCtrl,
                    hint: '--',
                    onChanged: (v) =>
                        ref.read(serverNameProvider.notifier).set(v),
                  ),
                ),
                if (savedNames.isNotEmpty)
                  GestureDetector(
                    onTap: () => _showServerPicker(context, savedNames, locale),
                    child: const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Icon(Icons.expand_more,
                          size: 18, color: AppColors.accent),
                    ),
                  ),
              ],
            ),
          ),
          const Gap(8),
          Container(width: 1, height: 32, color: AppColors.divider),
          const Gap(8),
          // Client field
          Expanded(
            child: _LabeledField(
              icon: Icons.face_outlined,
              label: AppStrings.t('client', locale),
              controller: _clientCtrl,
              hint: '--',
              onChanged: (v) => ref
                  .read(activeOrderProvider.notifier)
                  .setClientName(v),
            ),
          ),
        ],
      ),
    );
  }

  void _showServerPicker(
      BuildContext context, List<String> names, String locale) {
    final isAr = locale == 'ar';
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Gap(12),
            Text(
              isAr ? 'اختر الخادم' : 'Choisir le serveur',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
            const Gap(12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: names.map((name) {
                final isCurrent = _serveurCtrl.text == name;
                return GestureDetector(
                  onTap: () {
                    ref.read(serverNameProvider.notifier).set(name);
                    Navigator.pop(context);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isCurrent
                          ? AppColors.accent.withValues(alpha: 0.15)
                          : AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isCurrent
                            ? AppColors.accent
                            : AppColors.divider,
                      ),
                    ),
                    child: Text(
                      name,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isCurrent
                            ? AppColors.accent
                            : AppColors.textPrimary,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  final IconData icon;
  final String label;
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  const _LabeledField({
    required this.icon,
    required this.label,
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isCompact = size.width > size.height;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!isCompact)
          Row(
            children: [
              Icon(icon, size: 11, color: AppColors.textMuted),
              const Gap(3),
              Text(
                label,
                style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted),
              ),
            ],
          ),
        if (!isCompact) const Gap(2),
        SizedBox(
          height: isCompact ? 28 : 26,
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(
                  fontSize: 12, color: AppColors.textMuted),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide:
                    const BorderSide(color: AppColors.border, width: 1),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide:
                    const BorderSide(color: AppColors.border, width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide:
                    const BorderSide(color: AppColors.accent, width: 1.5),
              ),
              fillColor: AppColors.surfaceElevated,
              filled: true,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Ticket Title Bar ─────────────────────────────────────────────────────────

class _TicketTitleBar extends ConsumerStatefulWidget {
  final String locale;
  const _TicketTitleBar({required this.locale});

  @override
  ConsumerState<_TicketTitleBar> createState() => _TicketTitleBarState();
}

class _TicketTitleBarState extends ConsumerState<_TicketTitleBar> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
        text: ref.read(activeOrderProvider).ticketTitle);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale = widget.locale;
    ref.listen(activeOrderProvider, (prev, next) {
      if (next.ticketTitle != _ctrl.text) {
        _ctrl.text = next.ticketTitle;
      }
    });

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: Row(
        children: [
          Icon(Icons.edit_note_outlined,
              size: 18, color: AppColors.textMuted),
          const Gap(8),
          Expanded(
            child: TextField(
              controller: _ctrl,
              onChanged: (v) => ref
                  .read(activeOrderProvider.notifier)
                  .setTicketTitle(v),
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: locale == 'ar'
                    ? 'أعطِ عنواناً لطلبك...'
                    : 'Donnez un titre à votre ticket...',
                hintStyle: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                    fontStyle: FontStyle.italic),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 0, vertical: 4),
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Order Items List ─────────────────────────────────────────────────────────

class _OrderItemsList extends ConsumerWidget {
  final List<OrderItem> items;
  final String locale;
  final ScrollController? scrollController;

  const _OrderItemsList({
    required this.items,
    required this.locale,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: items.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, color: AppColors.divider),
      itemBuilder: (_, index) => _OrderItemTile(
        item: items[index],
        locale: locale,
      ),
    );
  }
}

class _OrderItemTile extends ConsumerWidget {
  final OrderItem item;
  final String locale;

  const _OrderItemTile({required this.item, required this.locale});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: AppColors.stockCritical,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) =>
          ref.read(activeOrderProvider.notifier).removeItem(item.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            _QtyControls(item: item),
            const Gap(10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    // Use stored product name — no more "Produit #ID"
                    locale == 'ar'
                        ? (item.productNameAr.isNotEmpty
                            ? item.productNameAr
                            : item.productNameFr)
                        : (item.productNameFr.isNotEmpty
                            ? item.productNameFr
                            : 'Produit #${item.productId}'),
                    style: TextStyle(
                      fontFamily: locale == 'ar' ? kCairoFont : null,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (item.notes != null && item.notes!.isNotEmpty)
                    Text(
                      item.notes!,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                ],
              ),
            ),
            const Gap(8),
            Text(
              CurrencyFormatter.format(item.lineTotal, locale: locale),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QtyControls extends ConsumerWidget {
  final OrderItem item;

  const _QtyControls({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _QtyBtn(
          icon: Icons.remove,
          onTap: () => ref
              .read(activeOrderProvider.notifier)
              .updateQuantity(item.id, item.quantity - 1),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            '${item.quantity}',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        _QtyBtn(
          icon: Icons.add,
          color: AppColors.accent,
          onTap: () => ref
              .read(activeOrderProvider.notifier)
              .updateQuantity(item.id, item.quantity + 1),
        ),
      ],
    );
  }
}

class _QtyBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;

  const _QtyBtn({required this.icon, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: (color ?? AppColors.textMuted).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: (color ?? AppColors.border).withValues(alpha: 0.5),
          ),
        ),
        child: Icon(
          icon,
          size: 14,
          color: color ?? AppColors.textSecondary,
        ),
      ),
    );
  }
}

// ─── Total Row ────────────────────────────────────────────────────────────────

class _TotalRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _TotalRow({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 13, color: AppColors.textSecondary)),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: valueColor ?? AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

// ─── Empty Order State ────────────────────────────────────────────────────────

class _EmptyOrderState extends StatelessWidget {
  final String locale;
  const _EmptyOrderState({required this.locale});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.shopping_bag_outlined,
                size: 32, color: AppColors.textMuted),
          ),
          const Gap(12),
          Text(
            AppStrings.t('empty_order', locale),
            style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600),
          ),
          const Gap(6),
          Text(
            locale == 'ar'
                ? 'اضغط على منتج لإضافته'
                : 'Tapez sur un produit pour l\'ajouter',
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ─── Receipt Preview Screen ───────────────────────────────────────────────────

class _ReceiptPreviewDialog extends ConsumerStatefulWidget {
  final String locale;
  const _ReceiptPreviewDialog({required this.locale});

  @override
  ConsumerState<_ReceiptPreviewDialog> createState() =>
      _ReceiptPreviewDialogState();
}

class _ReceiptPreviewDialogState
    extends ConsumerState<_ReceiptPreviewDialog> {
  String _method = 'cash';
  final _amountCtrl = TextEditingController();
  final _tableCtrl = TextEditingController();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final tableNumber = ref.read(activeOrderProvider).tableNumber;
    if (tableNumber != null) _tableCtrl.text = '$tableNumber';
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _tableCtrl.dispose();
    super.dispose();
  }

  double get _amountPaid => double.tryParse(_amountCtrl.text) ?? 0.0;

  Future<Uint8List> _buildPdfBytes(
      ActiveOrderState order, String storeName) async {
    final isCash = _method == 'cash';
    final amountPaid = isCash ? _amountPaid : order.total;
    final change =
        isCash && amountPaid > order.total ? amountPaid - order.total : 0.0;
    final serveurName = ref.read(serverNameProvider);

    final doc = await PdfReceiptService.buildReceipt(
      storeName: storeName,
      orderId: order.orderId,
      tableNumber: order.tableNumber,
      items: order.items
          .map((i) => PdfReceiptItem(
                name: widget.locale == 'ar'
                    ? (i.productNameAr.isNotEmpty
                        ? i.productNameAr
                        : i.productNameFr)
                    : i.productNameFr,
                qty: i.quantity,
                unitPrice: i.unitPrice,
                lineTotal: i.lineTotal,
              ))
          .toList(),
      subtotal: order.subtotal,
      discountPercent: order.discountPercent,
      discountFixed: order.discountFixed,
      total: order.total,
      amountPaid: amountPaid,
      change: change,
      paymentMethod: _method,
      date: DateTime.now(),
      serveurName: serveurName,
      clientName: order.clientName,
      ticketTitle: order.ticketTitle,
      locale: widget.locale,
    );
    return doc.save();
  }

  void _holdOrder() {
    ref.read(activeOrderProvider.notifier).holdOrder();
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _finalize() async {
    setState(() => _loading = true);
    try {
      await ref.read(activeOrderProvider.notifier).sendToKitchen(paymentMethod: _method);
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _printAndFinalize() async {
    final order = ref.read(activeOrderProvider);
    final storeName =
        ref.read(brandingProvider).valueOrNull?.storeName ?? 'ServePoint';

    setState(() => _loading = true);
    try {
      await Printing.layoutPdf(
        name: 'Ticket #${order.orderId ?? ''}',
        onLayout: (_) => _buildPdfBytes(order, storeName),
      );
      await ref.read(activeOrderProvider.notifier).sendToKitchen(paymentMethod: _method);
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Payment panel (shared between portrait and landscape) ───────────────────

  Widget _buildPaymentPanel(
      BuildContext context, String locale, double change, bool isCash) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Table number
          TextField(
            controller: _tableCtrl,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              labelText: AppStrings.t('table_number_label', locale),
              prefixIcon: const Icon(Icons.table_restaurant_outlined,
                  color: AppColors.textMuted, size: 18),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            onChanged: (v) {
              final n = int.tryParse(v);
              ref.read(activeOrderProvider.notifier).setTableNumber(n);
              setState(() {});
            },
          ),
          const Gap(8),

          // Payment method
          Row(
            children: [
              _PayMethodBtn(
                icon: Icons.money,
                label: AppStrings.t('pay_cash', locale),
                color: AppColors.accentGreen,
                selected: _method == 'cash',
                onTap: () => setState(() => _method = 'cash'),
              ),
              const Gap(6),
              _PayMethodBtn(
                icon: Icons.credit_card,
                label: AppStrings.t('pay_card', locale),
                color: AppColors.accent,
                selected: _method == 'card',
                onTap: () => setState(() => _method = 'card'),
              ),
              const Gap(6),
              _PayMethodBtn(
                icon: Icons.phone_android,
                label: AppStrings.t('pay_mobile', locale),
                color: AppColors.accentAmber,
                selected: _method == 'mobile',
                onTap: () => setState(() => _method = 'mobile'),
              ),
            ],
          ),

          // Cash amount & change
          if (isCash) ...[
            const Gap(8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 13),
                    decoration: InputDecoration(
                      labelText: AppStrings.t('amount_received_label', locale),
                      prefixIcon: const Icon(Icons.payments_outlined,
                          color: AppColors.textMuted, size: 18),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                if (_amountPaid > 0) ...[
                  const Gap(8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: change >= 0
                          ? AppColors.accentGreen.withValues(alpha: 0.1)
                          : AppColors.stockCritical.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: change >= 0
                            ? AppColors.accentGreen
                            : AppColors.stockCritical,
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          AppStrings.t('receipt_change', locale),
                          style: const TextStyle(
                              fontSize: 10, color: AppColors.textMuted),
                        ),
                        Text(
                          change >= 0
                              ? CurrencyFormatter.format(change,
                                  locale: locale)
                              : AppStrings.t('insufficient', locale),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: change >= 0
                                ? AppColors.accentGreen
                                : AppColors.stockCritical,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ],

          const Gap(10),

          // Action buttons — 2 rows of 2
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back, size: 15),
                  label: Text(AppStrings.t('back_btn', locale),
                      style: const TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    side: const BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const Gap(6),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _holdOrder,
                  icon: const Icon(Icons.pause_circle_outline, size: 15),
                  label: Text(
                    AppStrings.t('on_hold', locale),
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.accentAmber,
                    side: const BorderSide(color: AppColors.accentAmber),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ),
          const Gap(6),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _loading ? null : _finalize,
                  icon: const Icon(Icons.check_circle, size: 16),
                  label: Text(
                    AppStrings.t('validate_btn', locale),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const Gap(6),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _loading ? null : _printAndFinalize,
                  icon: _loading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.print, size: 16),
                  label: Text(
                    AppStrings.t('print_validate', locale),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 12),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accentGreen,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locale = widget.locale;
    final size = MediaQuery.sizeOf(context);
    final isLandscape = size.width > size.height;

    final order = ref.watch(activeOrderProvider);
    final storeName =
        ref.watch(brandingProvider).valueOrNull?.storeName ?? 'ServePoint';
    final serveurName = ref.watch(serverNameProvider);

    final isCash = _method == 'cash';
    final amountPaid = isCash ? _amountPaid : order.total;
    final change =
        isCash && amountPaid > order.total ? amountPaid - order.total : 0.0;

    final receiptPreview = LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: constraints.maxHeight - 48,
          ),
          child: Center(
            child: _ReceiptWidget(
              order: order,
              storeName: storeName,
              locale: locale,
              method: _method,
              amountPaid: amountPaid,
              serveurName: serveurName,
            ),
          ),
        ),
      ),
    );

    final paymentPanel = _buildPaymentPanel(context, locale, change, isCash);

    return Dialog(
      backgroundColor: AppColors.background,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isLandscape ? 16 : 20,
        vertical: isLandscape ? 12 : 24,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: isLandscape
            ? SizedBox(
                height: size.height - 24,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Left: scrollable receipt preview
                    Expanded(
                      child: Container(
                        color: AppColors.background,
                        child: receiptPreview,
                      ),
                    ),
                    // Right: payment panel (fixed 310dp wide)
                    SizedBox(
                      width: 310,
                      child: Container(
                        color: AppColors.surfaceCard,
                        child: SingleChildScrollView(child: paymentPanel),
                      ),
                    ),
                  ],
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Top: receipt preview constrained to 45% screen height
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: size.height * 0.45,
                    ),
                    child: Container(
                      color: AppColors.background,
                      child: receiptPreview,
                    ),
                  ),
                  // Bottom: payment panel
                  Container(
                    color: AppColors.surfaceCard,
                    child: paymentPanel,
                  ),
                ],
              ),
      ),
    );
  }
}

// ─── Receipt Widget (Flutter-rendered preview) ────────────────────────────────

class _ReceiptWidget extends StatelessWidget {
  final ActiveOrderState order;
  final String storeName;
  final String locale;
  final String method;
  final double amountPaid;
  final String serveurName;

  const _ReceiptWidget({
    required this.order,
    required this.storeName,
    required this.locale,
    required this.method,
    required this.amountPaid,
    this.serveurName = '',
  });

  @override
  Widget build(BuildContext context) {
    final isCash = method == 'cash';
    final hasDiscount =
        order.discountPercent > 0 || order.discountFixed > 0;
    final discountAmt =
        (order.subtotal * order.discountPercent / 100) + order.discountFixed;
    final change =
        isCash && amountPaid > order.total ? amountPaid - order.total : 0.0;

    final now = DateTime.now();
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}'
        '  ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    const paperW = 360.0;
    const baseStyle = TextStyle(fontSize: 15, color: Color(0xFF111111));
    const boldStyle = TextStyle(
        fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF111111));
    const mutedStyle = TextStyle(fontSize: 13, color: Color(0xFF666666));

    return Container(
      width: paperW,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Store name
          Center(
            child: Text(
              storeName,
              style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF111111)),
            ),
          ),
          const Gap(4),
          Center(child: Text(dateStr, style: mutedStyle)),
          const Gap(8),

          // Chips
          Wrap(
            spacing: 6,
            runSpacing: 4,
            alignment: WrapAlignment.center,
            children: [
              if (order.tableNumber != null)
                _chip('${AppStrings.t('table_prefix', locale)} ${order.tableNumber}'),
              if (order.orderId != null) _chip('#${order.orderId}'),
              if (serveurName.isNotEmpty)
                _chip('${AppStrings.t('server', locale)}: $serveurName'),
              if (order.clientName.isNotEmpty)
                _chip('${AppStrings.t('client', locale)}: ${order.clientName}'),
            ],
          ),

          if (order.ticketTitle.isNotEmpty) ...[
            const Gap(6),
            Center(
              child: Text(order.ticketTitle,
                  style: mutedStyle.copyWith(
                      fontStyle: FontStyle.italic)),
            ),
          ],

          const Gap(10),
          const Divider(height: 1, color: Color(0xFFCCCCCC)),
          const Gap(6),

          // Column headers
          Row(children: [
            Expanded(
                child: Text(AppStrings.t('receipt_article', locale),
                    style: boldStyle)),
            SizedBox(
                width: 32,
                child: Text(AppStrings.t('receipt_qty', locale),
                    style: boldStyle,
                    textAlign: TextAlign.center)),
            SizedBox(
                width: 56,
                child: Text(AppStrings.t('receipt_total_col', locale),
                    style: boldStyle,
                    textAlign: TextAlign.right)),
          ]),
          const Gap(4),
          const Divider(height: 1, color: Color(0xFFCCCCCC)),
          const Gap(4),

          // Items
          ...order.items.map((item) {
            final name = locale == 'ar'
                ? (item.productNameAr.isNotEmpty
                    ? item.productNameAr
                    : item.productNameFr)
                : (item.productNameFr.isNotEmpty
                    ? item.productNameFr
                    : 'Produit #${item.productId}');
            return Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Text(name, style: baseStyle)),
                  SizedBox(
                      width: 32,
                      child: Text('×${item.quantity}',
                          style: baseStyle,
                          textAlign: TextAlign.center)),
                  SizedBox(
                      width: 56,
                      child: Text(
                          item.lineTotal.toStringAsFixed(2),
                          style: baseStyle,
                          textAlign: TextAlign.right)),
                ],
              ),
            );
          }),

          const Gap(6),
          const Divider(height: 1, color: Color(0xFFCCCCCC)),
          const Gap(6),

          // Subtotal
          _totalRow(AppStrings.t('subtotal', locale),
              '${order.subtotal.toStringAsFixed(2)} ${CurrencyFormatter.currentCurrency}', baseStyle),

          // Discount
          if (hasDiscount) ...[
            const Gap(3),
            _totalRow(
              AppStrings.t('discount', locale),
              '- ${discountAmt.toStringAsFixed(2)} ${CurrencyFormatter.currentCurrency}',
              const TextStyle(
                  fontSize: 12, color: Color(0xFF2E7D32)),
            ),
          ],

          const Gap(6),
          const Divider(height: 2, color: Color(0xFF111111)),
          const Gap(6),

          // Total
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(AppStrings.t('total', locale),
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF111111))),
              Text('${order.total.toStringAsFixed(2)} ${CurrencyFormatter.currentCurrency}',
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFFD32F2F))),
            ],
          ),

          // Cash section
          if (isCash && amountPaid > 0) ...[
            const Gap(8),
            const Divider(height: 1, color: Color(0xFFCCCCCC)),
            const Gap(6),
            _totalRow(AppStrings.t('receipt_received', locale),
                '${amountPaid.toStringAsFixed(2)} ${CurrencyFormatter.currentCurrency}', baseStyle),
            const Gap(3),
            _totalRow(
              AppStrings.t('receipt_change', locale),
              '${change.toStringAsFixed(2)} ${CurrencyFormatter.currentCurrency}',
              const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2E7D32)),
            ),
          ],

          const Gap(14),
          const Divider(height: 1, color: Color(0xFFCCCCCC)),
          const Gap(8),
          Center(
            child: Text(
              AppStrings.t('receipt_thanks', locale),
              style: boldStyle,
            ),
          ),
          const Gap(4),
          Center(
            child: Text('Powered by ServePoint',
                style: mutedStyle.copyWith(fontSize: 10)),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F0F0),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text,
          style: const TextStyle(fontSize: 11, color: Color(0xFF444444))),
    );
  }

  Widget _totalRow(String label, String value, TextStyle style) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text(value, style: style),
      ],
    );
  }
}

// ─── Payment Method Button ────────────────────────────────────────────────────

class _PayMethodBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _PayMethodBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? color.withValues(alpha: 0.12)
                : AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? color : AppColors.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon,
                  color: selected ? color : AppColors.textMuted, size: 20),
              const Gap(3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: selected ? color : AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
