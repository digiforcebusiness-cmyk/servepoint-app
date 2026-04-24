import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/providers/app_providers.dart';

// ─── Period ───────────────────────────────────────────────────────────────────

enum _Period { today, week, month }

(DateTime, DateTime) _rangeFor(_Period p) {
  final now = DateTime.now();
  switch (p) {
    case _Period.today:
      final s = DateTime(now.year, now.month, now.day);
      return (s, s.add(const Duration(days: 1)));
    case _Period.week:
      final mon = now.subtract(Duration(days: now.weekday - 1));
      return (DateTime(mon.year, mon.month, mon.day), now);
    case _Period.month:
      return (DateTime(now.year, now.month, 1), now);
  }
}

// ─── Data Model ───────────────────────────────────────────────────────────────

class _PeriodStats {
  final int ordersCount;
  final double revenue;
  final double avgTicket;
  final List<double> hourlyRevenue;
  final List<Order> topOrders;
  final Map<String, double> paymentBreakdown;
  final List<Map<String, dynamic>> topProducts;
  final int cancelledCount;

  const _PeriodStats({
    required this.ordersCount,
    required this.revenue,
    required this.avgTicket,
    required this.hourlyRevenue,
    required this.topOrders,
    required this.paymentBreakdown,
    required this.topProducts,
    required this.cancelledCount,
  });
}

// ─── Provider ─────────────────────────────────────────────────────────────────

/// Live-updating report stats. Re-emits whenever any order in the period
/// is created or updated (e.g. payment recorded → status inProgress/paid).
final reportStatsProvider =
    StreamProvider.family<_PeriodStats, _Period>((ref, period) {
  final db = ref.watch(appDatabaseProvider);
  final (start, end) = _rangeFor(period);

  // Watch the settled-orders stream — fires whenever an order changes.
  return db.watchSettledOrdersInRange(start, end).asyncMap((paid) async {
    final cancelledCount = await db.getCancelledCountInRange(start, end);

    // Use direct SQL JOIN query — reliable and efficient.
    final topProducts = await db.getTopProductsInRange(start, end);

    final revenue = paid.fold(0.0, (s, o) => s + o.totalPrice);
    final avgTicket = paid.isEmpty ? 0.0 : revenue / paid.length;

    final hourly = List<double>.filled(24, 0.0);
    for (final o in paid) {
      hourly[o.createdAt.hour] += o.totalPrice;
    }

    final breakdown = <String, double>{'cash': 0, 'card': 0, 'mobile': 0};
    for (final o in paid) {
      final m = o.paymentMethod ?? 'cash';
      breakdown[m] = (breakdown[m] ?? 0) + o.totalPrice;
    }

    final sortedOrders = List<Order>.from(paid)
      ..sort((a, b) => b.totalPrice.compareTo(a.totalPrice));

    return _PeriodStats(
      ordersCount: paid.length,
      revenue: revenue,
      avgTicket: avgTicket,
      hourlyRevenue: hourly,
      topOrders: sortedOrders.take(5).toList(),
      paymentBreakdown: breakdown,
      topProducts: topProducts,
      cancelledCount: cancelledCount,
    );
  });
});

// ─── Screen ───────────────────────────────────────────────────────────────────

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  _Period _period = _Period.today;
  bool _exporting = false;

  Future<void> _exportPdf(_PeriodStats stats, String locale) async {
    setState(() => _exporting = true);
    try {
      final branding = await ref.read(brandingProvider.future);
      final currency = CurrencyFormatter.currentCurrency;
      final (start, _) = _rangeFor(_period);

      final periodLabel = switch (_period) {
        _Period.today => locale == 'ar' ? 'اليوم' : "Aujourd'hui",
        _Period.week => locale == 'ar' ? 'هذا الأسبوع' : 'Cette semaine',
        _Period.month => locale == 'ar' ? 'هذا الشهر' : 'Ce mois',
      };

      final doc = await _buildReportPdf(
        stats: stats,
        locale: locale,
        storeName: branding.storeName,
        currency: currency,
        periodLabel: periodLabel,
        date: start,
      );

      final bytes = await doc.save();

      Directory? dir;
      try {
        dir = await getDownloadsDirectory();
      } catch (_) {}
      dir ??= await getApplicationDocumentsDirectory();

      final slug = switch (_period) {
        _Period.today => 'today',
        _Period.week => 'week',
        _Period.month => 'month',
      };
      final fileName =
          'report_${slug}_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf';
      final file =
          File('${dir.path}${Platform.pathSeparator}$fileName');
      await file.writeAsBytes(bytes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              locale == 'ar'
                  ? 'تم حفظ التقرير: ${file.path}'
                  : 'Rapport sauvegardé : ${file.path}',
            ),
            backgroundColor: AppColors.accentGreen,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur export: $e'),
            backgroundColor: AppColors.stockCritical,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(appLocaleProvider);
    final statsAsync = ref.watch(reportStatsProvider(_period));
    final stats = statsAsync.value;

    return Column(
      children: [
        // Header bar
        Container(
          color: AppColors.primary,
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          child: Row(
            children: [
              const Icon(Icons.bar_chart, color: AppColors.accent, size: 20),
              const Gap(8),
              Text(
                AppStrings.t('reports_title', locale),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const Gap(6),
              Text(
                '— ${DateFormat('dd/MM/yyyy').format(DateTime.now())}',
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
              const Spacer(),
              _PeriodSelector(
                selected: _period,
                locale: locale,
                onChanged: (p) => setState(() => _period = p),
              ),
              const Gap(4),
              // Download button — enabled only when data is ready
              _exporting
                  ? const SizedBox(
                      width: 32,
                      height: 32,
                      child: Center(
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.accent,
                          ),
                        ),
                      ),
                    )
                  : IconButton(
                      onPressed:
                          stats != null ? () => _exportPdf(stats, locale) : null,
                      icon: const Icon(Icons.download_outlined),
                      color: stats != null
                          ? AppColors.accent
                          : AppColors.textMuted,
                      iconSize: 20,
                      tooltip: locale == 'ar'
                          ? 'تنزيل PDF'
                          : 'Télécharger PDF',
                      padding: const EdgeInsets.all(6),
                      constraints: const BoxConstraints(),
                    ),
            ],
          ),
        ),
        // Body
        Expanded(
          child: statsAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Text('Erreur: $e',
                  style:
                      const TextStyle(color: AppColors.stockCritical)),
            ),
            data: (stats) => _ReportContent(
              stats: stats,
              locale: locale,
              period: _period,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── PDF Builder ──────────────────────────────────────────────────────────────

Future<pw.Document> _buildReportPdf({
  required _PeriodStats stats,
  required String locale,
  required String storeName,
  required String currency,
  required String periodLabel,
  required DateTime date,
}) async {
  final isAr = locale == 'ar';

  // Fonts — Cairo covers Arabic + Latin; Nunito for Latin-only locales.
  final pw.Font regular;
  final pw.Font bold;
  final pw.Font extraBold;
  if (isAr) {
    regular = await PdfGoogleFonts.cairoRegular();
    bold = await PdfGoogleFonts.cairoBold();
    extraBold = await PdfGoogleFonts.cairoExtraBold();
  } else {
    regular = await PdfGoogleFonts.nunitoRegular();
    bold = await PdfGoogleFonts.nunitoBold();
    extraBold = await PdfGoogleFonts.nunitoExtraBold();
  }

  const accent = PdfColor.fromInt(0xFFE94560);
  const dark = PdfColor.fromInt(0xFF0D2137);
  const muted = PdfColor.fromInt(0xFF7A8FA6);
  const divider = PdfColor.fromInt(0xFFE2E8F0);
  const green = PdfColor.fromInt(0xFF22C55E);
  const amber = PdfColor.fromInt(0xFFF59E0B);

  pw.TextStyle ts(double size,
          {pw.Font? font,
          PdfColor color = const PdfColor(0.06, 0.13, 0.22),
          pw.FontWeight fw = pw.FontWeight.normal}) =>
      pw.TextStyle(
        font: font ?? regular,
        fontSize: size,
        color: color,
        fontWeight: fw,
      );

  String fmt(double v) =>
      '${v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(2)} $currency';

  // Payment labels
  final payLabels = {
    'cash': isAr ? 'نقداً' : 'Espèces',
    'card': isAr ? 'بطاقة' : 'Carte',
    'mobile': isAr ? 'موبايل' : 'Mobile',
  };

  final doc = pw.Document(title: 'Rapport $periodLabel');

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      textDirection: isAr ? pw.TextDirection.rtl : pw.TextDirection.ltr,
      margin: const pw.EdgeInsets.all(32),
      build: (ctx) => [
        // ── Header ────────────────────────────────────────────────────────
        pw.Container(
          padding: const pw.EdgeInsets.all(16),
          decoration: pw.BoxDecoration(
            color: dark,
            borderRadius: pw.BorderRadius.circular(10),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(storeName,
                      style: ts(18, font: extraBold, color: PdfColors.white)),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    isAr ? 'تقرير المبيعات — $periodLabel' : 'Rapport de ventes — $periodLabel',
                    style: ts(10, color: const PdfColor(0.6, 0.75, 0.85)),
                  ),
                ],
              ),
              pw.Text(
                DateFormat('dd/MM/yyyy').format(date),
                style: ts(11, font: bold, color: const PdfColor(0.6, 0.75, 0.85)),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 20),

        // ── KPI Row ───────────────────────────────────────────────────────
        pw.Row(children: [
          _pdfKpi(
            label: isAr ? 'الإيرادات' : 'Chiffre d\'affaires',
            value: fmt(stats.revenue),
            color: green,
            regular: regular, bold: bold,
          ),
          pw.SizedBox(width: 10),
          _pdfKpi(
            label: isAr ? 'الطلبات' : 'Commandes',
            value: '${stats.ordersCount}',
            color: accent,
            regular: regular, bold: bold,
          ),
          pw.SizedBox(width: 10),
          _pdfKpi(
            label: isAr ? 'متوسط الفاتورة' : 'Ticket moyen',
            value: fmt(stats.avgTicket),
            color: amber,
            regular: regular, bold: bold,
          ),
          pw.SizedBox(width: 10),
          _pdfKpi(
            label: isAr ? 'ملغاة' : 'Annulées',
            value: '${stats.cancelledCount}',
            color: const PdfColor(0.91, 0.27, 0.37),
            regular: regular, bold: bold,
          ),
        ]),
        pw.SizedBox(height: 20),

        // ── Payment Breakdown ─────────────────────────────────────────────
        _pdfSectionTitle(isAr ? 'المدفوعات' : 'Répartition des paiements',
            bold: bold),
        pw.SizedBox(height: 8),
        pw.Table(
          border: pw.TableBorder.all(color: divider, width: 0.5),
          columnWidths: {
            0: const pw.FlexColumnWidth(3),
            1: const pw.FlexColumnWidth(2),
            2: const pw.FlexColumnWidth(2),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColor(0.94, 0.96, 0.99)),
              children: [
                _pdfCell(isAr ? 'وسيلة الدفع' : 'Méthode', bold, isHeader: true),
                _pdfCell(isAr ? 'المبلغ' : 'Montant', bold, isHeader: true),
                _pdfCell(isAr ? 'النسبة' : 'Part', bold, isHeader: true),
              ],
            ),
            for (final method in ['cash', 'card', 'mobile']) ...[
              pw.TableRow(children: [
                _pdfCell(payLabels[method]!, regular),
                _pdfCell(fmt(stats.paymentBreakdown[method] ?? 0), regular),
                _pdfCell(
                  stats.revenue > 0
                      ? '${((stats.paymentBreakdown[method] ?? 0) / stats.revenue * 100).toStringAsFixed(1)}%'
                      : '—',
                  regular,
                ),
              ]),
            ],
          ],
        ),
        pw.SizedBox(height: 20),

        // ── Top Products ──────────────────────────────────────────────────
        if (stats.topProducts.isNotEmpty) ...[
          _pdfSectionTitle(
              isAr ? 'أفضل المنتجات' : 'Produits les plus vendus',
              bold: bold),
          pw.SizedBox(height: 8),
          pw.Table(
            border: pw.TableBorder.all(color: divider, width: 0.5),
            columnWidths: {
              0: const pw.FixedColumnWidth(24),
              1: const pw.FlexColumnWidth(4),
              2: const pw.FlexColumnWidth(1.5),
              3: const pw.FlexColumnWidth(2),
            },
            children: [
              pw.TableRow(
                decoration:
                    const pw.BoxDecoration(color: PdfColor(0.94, 0.96, 0.99)),
                children: [
                  _pdfCell('#', bold, isHeader: true),
                  _pdfCell(isAr ? 'المنتج' : 'Produit', bold, isHeader: true),
                  _pdfCell(isAr ? 'الكمية' : 'Qté', bold, isHeader: true),
                  _pdfCell(isAr ? 'الإيراد' : 'CA', bold, isHeader: true),
                ],
              ),
              for (int i = 0; i < stats.topProducts.length; i++) ...[
                pw.TableRow(
                  decoration: i.isEven
                      ? null
                      : const pw.BoxDecoration(
                          color: PdfColor(0.98, 0.98, 0.99)),
                  children: [
                    _pdfCell('${i + 1}', regular),
                    _pdfCell(
                      isAr
                          ? (stats.topProducts[i]['nameAr'] as String).isNotEmpty
                              ? stats.topProducts[i]['nameAr'] as String
                              : stats.topProducts[i]['nameFr'] as String
                          : stats.topProducts[i]['nameFr'] as String,
                      regular,
                    ),
                    _pdfCell(
                        '× ${stats.topProducts[i]['totalQty']}', regular),
                    _pdfCell(
                        fmt((stats.topProducts[i]['totalRevenue'] as num)
                            .toDouble()),
                        regular),
                  ],
                ),
              ],
            ],
          ),
          pw.SizedBox(height: 20),
        ],

        // ── Top Orders ────────────────────────────────────────────────────
        if (stats.topOrders.isNotEmpty) ...[
          _pdfSectionTitle(
              isAr ? 'أعلى الطلبات' : 'Meilleures commandes',
              bold: bold),
          pw.SizedBox(height: 8),
          pw.Table(
            border: pw.TableBorder.all(color: divider, width: 0.5),
            columnWidths: {
              0: const pw.FixedColumnWidth(24),
              1: const pw.FlexColumnWidth(1.5),
              2: const pw.FlexColumnWidth(2.5),
              3: const pw.FlexColumnWidth(1.5),
              4: const pw.FlexColumnWidth(2),
            },
            children: [
              pw.TableRow(
                decoration:
                    const pw.BoxDecoration(color: PdfColor(0.94, 0.96, 0.99)),
                children: [
                  _pdfCell('#', bold, isHeader: true),
                  _pdfCell(isAr ? 'رقم' : 'N°', bold, isHeader: true),
                  _pdfCell(isAr ? 'النوع' : 'Type', bold, isHeader: true),
                  _pdfCell(isAr ? 'الدفع' : 'Paiement', bold, isHeader: true),
                  _pdfCell(isAr ? 'المجموع' : 'Total', bold, isHeader: true),
                ],
              ),
              for (int i = 0; i < stats.topOrders.length; i++) ...[
                pw.TableRow(
                  decoration: i.isEven
                      ? null
                      : const pw.BoxDecoration(
                          color: PdfColor(0.98, 0.98, 0.99)),
                  children: [
                    _pdfCell('${i + 1}', regular),
                    _pdfCell('#${stats.topOrders[i].id}', regular),
                    _pdfCell(_orderTypeLabel(stats.topOrders[i], isAr),
                        regular),
                    _pdfCell(
                        payLabels[stats.topOrders[i].paymentMethod] ??
                            stats.topOrders[i].paymentMethod ??
                            '—',
                        regular),
                    _pdfCell(fmt(stats.topOrders[i].totalPrice), regular),
                  ],
                ),
              ],
            ],
          ),
        ],

        // ── Footer ────────────────────────────────────────────────────────
        pw.SizedBox(height: 24),
        pw.Divider(color: divider),
        pw.SizedBox(height: 6),
        pw.Center(
          child: pw.Text(
            'ServePoint POS — ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
            style: ts(8, color: muted),
          ),
        ),
      ],
    ),
  );

  return doc;
}

pw.Widget _pdfKpi({
  required String label,
  required String value,
  required PdfColor color,
  required pw.Font regular,
  required pw.Font bold,
}) =>
    pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: const PdfColor(0.88, 0.92, 0.96)),
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(value,
                style: pw.TextStyle(
                    font: bold, fontSize: 16, color: color)),
            pw.SizedBox(height: 2),
            pw.Text(label,
                style: pw.TextStyle(
                    font: regular, fontSize: 8,
                    color: const PdfColor(0.47, 0.56, 0.64))),
          ],
        ),
      ),
    );

pw.Widget _pdfSectionTitle(String text, {required pw.Font bold}) =>
    pw.Text(text,
        style: pw.TextStyle(
            font: bold,
            fontSize: 12,
            color: const PdfColor(0.06, 0.13, 0.22)));

pw.Widget _pdfCell(String text, pw.Font font,
    {bool isHeader = false}) =>
    pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          font: font,
          fontSize: 9,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: isHeader
              ? const PdfColor(0.06, 0.13, 0.22)
              : const PdfColor(0.2, 0.28, 0.36),
        ),
      ),
    );

String _orderTypeLabel(Order order, bool isAr) {
  switch (order.orderType) {
    case 'surPlace':
      return order.tableNumber != null
          ? (isAr ? 'طاولة ${order.tableNumber}' : 'Table ${order.tableNumber}')
          : (isAr ? 'في المحل' : 'Sur place');
    case 'emporter':
      return isAr ? 'للأخذ' : 'À emporter';
    default:
      return isAr ? 'توصيل' : 'Livraison';
  }
}

// ─── Period Selector ──────────────────────────────────────────────────────────

class _PeriodSelector extends StatelessWidget {
  final _Period selected;
  final String locale;
  final ValueChanged<_Period> onChanged;

  const _PeriodSelector({
    required this.selected,
    required this.locale,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final labels = {
      _Period.today: AppStrings.t('period_today', locale),
      _Period.week: AppStrings.t('period_week', locale),
      _Period.month: AppStrings.t('period_month', locale),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: _Period.values.map((p) {
        final isSel = p == selected;
        return Padding(
          padding: const EdgeInsets.only(left: 4),
          child: GestureDetector(
            onTap: () => onChanged(p),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: isSel
                    ? AppColors.accent
                    : AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSel ? AppColors.accent : AppColors.border,
                ),
              ),
              child: Text(
                labels[p]!,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isSel ? Colors.white : AppColors.textSecondary,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─── Report Content ───────────────────────────────────────────────────────────

class _ReportContent extends StatelessWidget {
  final _PeriodStats stats;
  final String locale;
  final _Period period;

  const _ReportContent({
    required this.stats,
    required this.locale,
    required this.period,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. KPI 2×2 grid
          _KpiGrid(stats: stats, locale: locale),
          const Gap(20),

          // 2. Payment breakdown
          _SectionTitle(
            icon: Icons.payments_outlined,
            title: AppStrings.t('payment_breakdown', locale),
          ),
          const Gap(10),
          _PaymentBreakdown(
            breakdown: stats.paymentBreakdown,
            total: stats.revenue,
            locale: locale,
          ),
          const Gap(20),

          // 3. Hourly chart — today only
          if (period == _Period.today) ...[
            _SectionTitle(
              icon: Icons.bar_chart,
              title: AppStrings.t('hourly_revenue', locale),
            ),
            const Gap(10),
            _HourlyBarChart(
                hourlyRevenue: stats.hourlyRevenue, locale: locale),
            const Gap(20),
          ],

          // 4. Top products
          _SectionTitle(
            icon: Icons.star_outline,
            title: AppStrings.t('top_products', locale),
          ),
          const Gap(10),
          _TopProductsList(products: stats.topProducts, locale: locale),
          const Gap(20),

          // 5. Top orders
          _SectionTitle(
            icon: Icons.emoji_events_outlined,
            title: AppStrings.t('top_orders', locale),
          ),
          const Gap(10),
          _TopOrdersList(orders: stats.topOrders, locale: locale),
          const Gap(20),
        ],
      ),
    );
  }
}

// ─── KPI Grid (2×2) ───────────────────────────────────────────────────────────

class _KpiGrid extends StatelessWidget {
  final _PeriodStats stats;
  final String locale;

  const _KpiGrid({required this.stats, required this.locale});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _KpiCard(
                icon: Icons.trending_up,
                color: AppColors.accentGreen,
                label: AppStrings.t('kpi_revenue', locale),
                value: CurrencyFormatter.formatCompact(stats.revenue,
                    locale: locale),
              ),
            ),
            const Gap(10),
            Expanded(
              child: _KpiCard(
                icon: Icons.analytics_outlined,
                color: AppColors.accentAmber,
                label: AppStrings.t('kpi_avg_ticket', locale),
                value: CurrencyFormatter.formatCompact(stats.avgTicket,
                    locale: locale),
              ),
            ),
          ],
        ),
        const Gap(10),
        Row(
          children: [
            Expanded(
              child: _KpiCard(
                icon: Icons.receipt_long_outlined,
                color: AppColors.accent,
                label: AppStrings.t('kpi_orders', locale),
                value: '${stats.ordersCount}',
              ),
            ),
            const Gap(10),
            Expanded(
              child: _KpiCard(
                icon: Icons.cancel_outlined,
                color: AppColors.stockCritical,
                label: AppStrings.t('kpi_cancelled', locale),
                value: '${stats.cancelledCount}',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  const _KpiCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const Gap(10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Payment Breakdown ────────────────────────────────────────────────────────

class _PaymentBreakdown extends StatelessWidget {
  final Map<String, double> breakdown;
  final double total;
  final String locale;

  const _PaymentBreakdown({
    required this.breakdown,
    required this.total,
    required this.locale,
  });

  static const _methods = ['cash', 'card', 'mobile'];
  static const _colors = [
    AppColors.accentGreen,
    AppColors.accent,
    AppColors.accentAmber,
  ];

  @override
  Widget build(BuildContext context) {
    final labels = {
      'cash': AppStrings.t('pay_cash', locale),
      'card': AppStrings.t('pay_card', locale),
      'mobile': AppStrings.t('pay_mobile', locale),
    };

    if (total <= 0) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Center(
          child: Text(
            AppStrings.t('no_data', locale),
            style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          // Segmented bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 14,
              child: Row(
                children: List.generate(_methods.length, (i) {
                  final ratio = (breakdown[_methods[i]] ?? 0) / total;
                  final flex = (ratio * 1000).round().clamp(1, 1000);
                  return Expanded(
                    flex: flex,
                    child: Container(color: _colors[i]),
                  );
                }),
              ),
            ),
          ),
          const Gap(12),
          // Legend
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(_methods.length, (i) {
              final method = _methods[i];
              final color = _colors[i];
              final amount = breakdown[method] ?? 0;
              return Column(
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const Gap(4),
                      Text(
                        labels[method]!,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const Gap(3),
                  Text(
                    CurrencyFormatter.formatCompact(amount, locale: locale),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }
}

// ─── Hourly Bar Chart ─────────────────────────────────────────────────────────

class _HourlyBarChart extends StatelessWidget {
  final List<double> hourlyRevenue;
  final String locale;

  const _HourlyBarChart(
      {required this.hourlyRevenue, required this.locale});

  @override
  Widget build(BuildContext context) {
    final maxVal =
        hourlyRevenue.reduce((a, b) => a > b ? a : b);
    final maxY = (maxVal * 1.2).clamp(10.0, double.infinity);

    return Container(
      height: 180,
      padding: const EdgeInsets.fromLTRB(0, 12, 12, 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: BarChart(
        BarChartData(
          maxY: maxY,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
                '${group.x}h\n${rod.toY.toStringAsFixed(0)} ${CurrencyFormatter.currentCurrency}',
                const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (v, _) {
                  if (v % 6 != 0) return const SizedBox.shrink();
                  return Text(
                    '${v.toInt()}h',
                    style: const TextStyle(
                        fontSize: 9, color: AppColors.textMuted),
                  );
                },
                reservedSize: 18,
              ),
            ),
            leftTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: maxY / 4,
            getDrawingHorizontalLine: (_) => FlLine(
              color: AppColors.divider,
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: List.generate(24, (i) {
            final val = hourlyRevenue[i];
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: val,
                  width: 8,
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(3)),
                  gradient: val > 0
                      ? LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            AppColors.accent.withValues(alpha: 0.6),
                            AppColors.accent,
                          ],
                        )
                      : LinearGradient(colors: [
                          AppColors.surfaceElevated,
                          AppColors.surfaceElevated,
                        ]),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

// ─── Top Products ─────────────────────────────────────────────────────────────

class _TopProductsList extends StatelessWidget {
  final List<Map<String, dynamic>> products;
  final String locale;

  const _TopProductsList({required this.products, required this.locale});

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Center(
          child: Text(
            AppStrings.t('no_sales', locale),
            style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: products.asMap().entries.map((e) {
          final rank = e.key + 1;
          final p = e.value;
          final nameAr = p['nameAr'] as String;
          final nameFr = p['nameFr'] as String;
          final name =
              locale == 'ar' && nameAr.isNotEmpty ? nameAr : nameFr;
          final qty = p['totalQty'] as int;
          final rev = p['totalRevenue'] as double;
          final isLast = rank == products.length;

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    _RankBadge(rank: rank),
                    const Gap(10),
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Gap(8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '× $qty',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const Gap(10),
                    Text(
                      CurrencyFormatter.format(rev, locale: locale),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isLast)
                const Divider(height: 1, color: AppColors.divider),
            ],
          );
        }).toList(),
      ),
    );
  }
}

// ─── Top Orders ───────────────────────────────────────────────────────────────

class _TopOrdersList extends StatelessWidget {
  final List<Order> orders;
  final String locale;

  const _TopOrdersList({required this.orders, required this.locale});

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Center(
          child: Text(
            AppStrings.t('no_orders_report', locale),
            style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: orders.asMap().entries.map((e) {
          final rank = e.key + 1;
          final order = e.value;
          final isLast = rank == orders.length;

          String typeLabel;
          switch (order.orderType) {
            case 'surPlace':
              typeLabel = order.tableNumber != null
                  ? '${AppStrings.t('table_short', locale)} ${order.tableNumber}'
                  : AppStrings.t('type_surplace', locale);
            case 'emporter':
              typeLabel = AppStrings.t('type_emporter', locale);
            default:
              typeLabel = AppStrings.t('type_delivery_full', locale);
          }

          final method = order.paymentMethod;
          final methodIcon = method == 'card'
              ? Icons.credit_card
              : method == 'mobile'
                  ? Icons.phone_android
                  : Icons.money;
          final methodColor = method == 'card'
              ? AppColors.accent
              : method == 'mobile'
                  ? AppColors.accentAmber
                  : AppColors.accentGreen;

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    _RankBadge(rank: rank),
                    const Gap(10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '#${order.id}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            typeLabel,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (method != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child:
                            Icon(methodIcon, size: 14, color: methodColor),
                      ),
                    Text(
                      CurrencyFormatter.format(order.totalPrice,
                          locale: locale),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.accent,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isLast)
                const Divider(height: 1, color: AppColors.divider),
            ],
          );
        }).toList(),
      ),
    );
  }
}

// ─── Rank Badge ───────────────────────────────────────────────────────────────

class _RankBadge extends StatelessWidget {
  final int rank;
  const _RankBadge({required this.rank});

  @override
  Widget build(BuildContext context) {
    final colors = {
      1: const Color(0xFFFFD700),
      2: const Color(0xFFC0C0C0),
      3: const Color(0xFFCD7F32),
    };
    final color = colors[rank] ?? AppColors.surfaceElevated;
    final textColor = rank <= 3 ? Colors.white : AppColors.textSecondary;

    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Center(
        child: Text(
          '$rank',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: textColor,
          ),
        ),
      ),
    );
  }
}

// ─── Section Title ────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionTitle({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.accent),
        const Gap(6),
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
