import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/printing/bluetooth_printer_service.dart';
import '../../../../core/printing/thermal_print_service.dart';
import '../../../../core/sync/sync_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../../qr_menu/presentation/screens/qr_menu_screen.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';

import '../../../subscription/presentation/paywall_screen.dart';
import '../../../subscription/subscription_provider.dart';
import '../../../subscription/subscription_service.dart';

// ─── Persisted settings providers ────────────────────────────────────────────

final restaurantNameProvider =
    StateNotifierProvider<PersistedStringNotifier, String>((ref) {
  return PersistedStringNotifier(
      ref.watch(appDatabaseProvider), 'store_name', '');
});

final restaurantAddressProvider =
    StateNotifierProvider<PersistedStringNotifier, String>((ref) {
  return PersistedStringNotifier(
      ref.watch(appDatabaseProvider), 'store_address', '');
});

final restaurantPhoneProvider =
    StateNotifierProvider<PersistedStringNotifier, String>((ref) {
  return PersistedStringNotifier(
      ref.watch(appDatabaseProvider), 'store_phone', '');
});

final paperWidthProvider =
    StateProvider<PaperWidth>((ref) => PaperWidth.mm80);

// ─── Settings Screen ──────────────────────────────────────────────────────────

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(appLocaleProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: Text(
          AppStrings.t('settings_title', locale),
          style: TextStyle(
            fontFamily: locale == 'ar' ? kCairoFont : null,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Restaurant Info ────────────────────────────────────────────────
          _SettingsSection(
            title: AppStrings.t('section_info', locale),
            icon: Icons.store,
            children: [
              _EditableTile(
                icon: Icons.restaurant,
                label: AppStrings.t('field_restaurant_name', locale),
                provider: restaurantNameProvider,
                locale: locale,
              ),
              _EditableTile(
                icon: Icons.location_on,
                label: AppStrings.t('field_address', locale),
                provider: restaurantAddressProvider,
                locale: locale,
              ),
              _EditableTile(
                icon: Icons.phone,
                label: AppStrings.t('field_phone', locale),
                provider: restaurantPhoneProvider,
                locale: locale,
              ),
            ],
          ),
          const Gap(16),

          // ── Language ───────────────────────────────────────────────────────
          _SettingsSection(
            title: AppStrings.t('section_language', locale),
            icon: Icons.language,
            children: [
              _LocaleTile(locale: locale),
            ],
          ),
          const Gap(16),

          // ── Currency ───────────────────────────────────────────────────────
          _SettingsSection(
            title: AppStrings.t('section_currency', locale),
            icon: Icons.attach_money,
            children: [
              _CurrencyTile(locale: locale),
            ],
          ),
          const Gap(16),

          // ── Printer ────────────────────────────────────────────────────────
          _SettingsSection(
            title: AppStrings.t('section_printer', locale),
            icon: Icons.print,
            children: [
              _PaperWidthTile(locale: locale),
              _PrinterPairingTile(locale: locale),
            ],
          ),
          const Gap(16),

          // ── Sync ───────────────────────────────────────────────────────────
          _SettingsSection(
            title: AppStrings.t('section_sync', locale),
            icon: Icons.cloud_sync,
            children: [
              _SyncStatusTile(locale: locale),
            ],
          ),
          const Gap(16),

          // ── Navigation shortcuts ───────────────────────────────────────────
          _SettingsSection(
            title: AppStrings.t('section_tools', locale),
            icon: Icons.build,
            children: [
              _NavTile(
                icon: Icons.qr_code_2,
                label: AppStrings.t('qr_menu', locale),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const QrMenuScreen()),
                ),
              ),
            ],
          ),
          const Gap(24),

          // ── Subscription ─────────────────────────────────────────────────
          _SubscriptionSection(locale: locale),

          const Gap(24),

          // App version
          const Center(
            child: Text(
              'ServePoint POS v1.0.0 — Offline-First',
              style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textMuted,
                  fontStyle: FontStyle.italic),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Section Wrapper ──────────────────────────────────────────────────────────

class _SettingsSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _SettingsSection({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 15, color: AppColors.accent),
            const Gap(6),
            Text(
              title,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.accent,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const Gap(8),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            children: children.asMap().entries.map((e) {
              final isLast = e.key == children.length - 1;
              return Column(
                children: [
                  e.value,
                  if (!isLast)
                    const Divider(
                        height: 1, color: AppColors.divider, indent: 48),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

// ─── Editable Tile ────────────────────────────────────────────────────────────

class _EditableTile extends ConsumerWidget {
  final IconData icon;
  final String label;
  final StateNotifierProvider<PersistedStringNotifier, String> provider;
  final String locale;

  const _EditableTile({
    required this.icon,
    required this.label,
    required this.provider,
    required this.locale,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(provider);

    return ListTile(
      leading: Icon(icon, color: AppColors.textSecondary, size: 20),
      title: Text(label,
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
      subtitle: Text(
        value,
        style: const TextStyle(
            fontSize: 14, color: AppColors.textPrimary, fontWeight: FontWeight.w500),
      ),
      trailing: const Icon(Icons.edit, size: 16, color: AppColors.textMuted),
      onTap: () => _showEditDialog(context, ref, value),
    );
  }

  void _showEditDialog(BuildContext context, WidgetRef ref, String current) {
    final ctrl = TextEditingController(text: current);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceCard,
        title: Text(label,
            style: const TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textDirection:
              locale == 'ar' ? TextDirection.rtl : TextDirection.ltr,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppStrings.t('cancel_dialog', locale),
                style: const TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              ref.read(provider.notifier).state = ctrl.text;
              Navigator.pop(context);
            },
            child: Text(AppStrings.t('save_btn', locale)),
          ),
        ],
      ),
    );
  }
}

// ─── Locale Tile ──────────────────────────────────────────────────────────────

const _kLanguages = [
  ('fr', '🇫🇷', 'Français'),
  ('en', '🇬🇧', 'English'),
  ('es', '🇪🇸', 'Español'),
  ('ar', '🇲🇦', 'العربية'),
];

class _LocaleTile extends ConsumerWidget {
  final String locale;
  const _LocaleTile({required this.locale});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppStrings.t('select_language', locale),
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _kLanguages.map((lang) {
              final (code, flag, label) = lang;
              final selected = locale == code;
              return GestureDetector(
                onTap: () => ref.read(appLocaleProvider.notifier).state = code,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.accent.withValues(alpha: 0.15) : AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected ? AppColors.accent : AppColors.divider,
                      width: selected ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(flag, style: const TextStyle(fontSize: 16)),
                      const SizedBox(width: 6),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                          color: selected ? AppColors.accent : AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ─── Currency Tile ─────────────────────────────────────────────────────────────

const _kCurrencies = [
  ('€', 'Euro (€)'),
  ('\$', 'US Dollar (\$)'),
  ('£', 'Pound (£)'),
  ('DH', 'Dirham (DH)'),
  ('د.إ', 'UAE Dirham'),
  ('ر.س', 'Saudi Riyal'),
  ('₺', 'Lira (₺)'),
  ('₹', 'Rupee (₹)'),
  ('¥', 'Yen (¥)'),
  ('CHF', 'Swiss Franc'),
  ('CA\$', 'CAD (CA\$)'),
  ('A\$', 'AUD (A\$)'),
];

class _CurrencyTile extends ConsumerWidget {
  final String locale;
  const _CurrencyTile({required this.locale});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(currencyProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppStrings.t('select_currency', locale),
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: _kCurrencies.any((c) => c.$1 == current) ? current : '€',
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: Text(
                current,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.accent),
              ),
            ),
            items: _kCurrencies.map((c) => DropdownMenuItem(
              value: c.$1,
              child: Text('${c.$1}  —  ${c.$2}'),
            )).toList(),
            onChanged: (v) {
              if (v != null) {
                ref.read(currencyProvider.notifier).state = v;
                CurrencyFormatter.currentCurrency = v;
              }
            },
          ),
        ],
      ),
    );
  }
}

// ─── Paper Width Tile ─────────────────────────────────────────────────────────

class _PaperWidthTile extends ConsumerWidget {
  final String locale;
  const _PaperWidthTile({required this.locale});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = ref.watch(paperWidthProvider);

    return ListTile(
      leading: const Icon(Icons.receipt, color: AppColors.textSecondary, size: 20),
      title: Text(
        AppStrings.t('paper_width', locale),
        style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
      ),
      trailing: SegmentedButton<PaperWidth>(
        style: SegmentedButton.styleFrom(
          backgroundColor: AppColors.surfaceElevated,
          selectedBackgroundColor: AppColors.accent,
          foregroundColor: AppColors.textSecondary,
          selectedForegroundColor: Colors.white,
          side: const BorderSide(color: AppColors.divider),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        segments: const [
          ButtonSegment(value: PaperWidth.mm58, label: Text('58mm')),
          ButtonSegment(value: PaperWidth.mm80, label: Text('80mm')),
        ],
        selected: {width},
        onSelectionChanged: (s) =>
            ref.read(paperWidthProvider.notifier).state = s.first,
      ),
    );
  }
}

// ─── Printer Pairing Tile ─────────────────────────────────────────────────────

class _PrinterPairingTile extends ConsumerWidget {
  final String locale;
  const _PrinterPairingTile({required this.locale});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedId = ref.watch(selectedPrinterIdProvider);

    return ListTile(
      leading: const Icon(Icons.bluetooth, color: AppColors.textSecondary, size: 20),
      title: Text(
        AppStrings.t('selected_printer', locale),
        style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
      ),
      subtitle: Text(
        selectedId ?? AppStrings.t('no_printer_selected', locale),
        style: TextStyle(
          fontSize: 13,
          color: selectedId != null ? AppColors.accentGreen : AppColors.textMuted,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: TextButton(
        onPressed: () => _showPrinterScan(context, ref),
        child: Text(
          AppStrings.t('scan_btn', locale),
          style: const TextStyle(color: AppColors.accent, fontSize: 13),
        ),
      ),
    );
  }

  void _showPrinterScan(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _PrinterScanSheet(
        locale: ref.read(appLocaleProvider),
      ),
    );
  }
}

// ─── Printer Scan Bottom Sheet ────────────────────────────────────────────────

class _PrinterScanSheet extends ConsumerWidget {
  final String locale;
  const _PrinterScanSheet({required this.locale});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scanAsync = ref.watch(printerScanResultsProvider);

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bluetooth_searching, color: AppColors.accent),
              const Gap(8),
              Text(
                AppStrings.t('searching_printers', locale),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const Gap(16),
          scanAsync.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (e, _) => Text(
              '$e',
              style: const TextStyle(color: AppColors.stockCritical),
            ),
            data: (results) {
              if (results.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      AppStrings.t('no_devices', locale),
                      style: const TextStyle(color: AppColors.textMuted),
                    ),
                  ),
                );
              }
              return ListView.builder(
                shrinkWrap: true,
                itemCount: results.length,
                itemBuilder: (_, i) {
                  final device = results[i].device;
                  final name = device.platformName.isEmpty
                      ? device.remoteId.str
                      : device.platformName;
                  return ListTile(
                    leading: const Icon(Icons.print, color: AppColors.textSecondary),
                    title: Text(name,
                        style: const TextStyle(color: AppColors.textPrimary)),
                    subtitle: Text(device.remoteId.str,
                        style: const TextStyle(
                            color: AppColors.textMuted, fontSize: 11)),
                    trailing: ElevatedButton(
                      onPressed: () async {
                        final service =
                            ref.read(bluetoothPrinterServiceProvider);
                        final connected = await service.connect(device);
                        if (connected) {
                          ref.read(selectedPrinterIdProvider.notifier).state =
                              name;
                          if (context.mounted) Navigator.pop(context);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8)),
                      child: Text(
                        AppStrings.t('connect', locale),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

// ─── Sync Status Tile ─────────────────────────────────────────────────────────

class _SyncStatusTile extends ConsumerWidget {
  final String locale;
  const _SyncStatusTile({required this.locale});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncState = ref.watch(syncServiceProvider);
    final pending = ref.watch(pendingSyncCountProvider);

    Color statusColor;
    String statusText;
    IconData statusIcon;

    switch (syncState.status) {
      case SyncStatus.syncing:
        statusColor = AppColors.accentAmber;
        statusText = AppStrings.t('syncing', locale);
        statusIcon = Icons.sync;
        break;
      case SyncStatus.success:
        statusColor = AppColors.accentGreen;
        statusText = AppStrings.t('synced', locale);
        statusIcon = Icons.cloud_done;
        break;
      case SyncStatus.failed:
        statusColor = AppColors.stockCritical;
        statusText = '${AppStrings.t('sync_failed', locale)} ($pending)';
        statusIcon = Icons.cloud_off;
        break;
      default:
        statusColor =
            pending > 0 ? AppColors.accentAmber : AppColors.accentGreen;
        statusText = pending > 0
            ? '$pending ${AppStrings.t('sync_pending', locale)}'
            : AppStrings.t('all_synced', locale);
        statusIcon = pending > 0 ? Icons.cloud_upload : Icons.cloud_done;
    }

    return ListTile(
      leading: Icon(statusIcon, color: statusColor, size: 20),
      title: Text(
        AppStrings.t('sync_status_label', locale),
        style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
      ),
      subtitle: Text(
        statusText,
        style: TextStyle(
          fontSize: 13,
          color: statusColor,
          fontWeight: FontWeight.w600,
        ),
      ),
      trailing: syncState.status != SyncStatus.syncing
          ? IconButton(
              icon: const Icon(Icons.refresh, color: AppColors.textMuted),
              onPressed: () =>
                  ref.read(syncServiceProvider.notifier).syncNow(),
              tooltip: AppStrings.t('sync_now', locale),
            )
          : const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
    );
  }
}

// ─── Subscription Section ─────────────────────────────────────────────────────

class _SubscriptionSection extends ConsumerWidget {
  final String locale;
  const _SubscriptionSection({required this.locale});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPro = ref.watch(isProProvider);
    final expiry = ref.watch(proExpiryProvider);

    return _SettingsSection(
      title: AppStrings.t('section_subscription', locale),
      icon: Icons.star_rounded,
      children: [
        // Current plan tile
        ListTile(
          leading: Icon(
            isPro ? Icons.star_rounded : Icons.star_outline_rounded,
            color: isPro ? AppColors.accentAmber : AppColors.textMuted,
            size: 20,
          ),
          title: Text(
            isPro
                ? 'ServePoint Pro'
                : AppStrings.t('free_plan', locale),
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary),
          ),
          subtitle: isPro && expiry != null
              ? Text(
                  '${AppStrings.t('expires_on', locale)} '
                  '${expiry.day}/${expiry.month}/${expiry.year}',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textMuted),
                )
              : null,
          trailing: isPro
              ? Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.accentAmber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'ACTIF',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: AppColors.accentAmber,
                    ),
                  ),
                )
              : null,
        ),
        // Upgrade / Manage button
        if (!isPro)
          ListTile(
            leading: const Icon(Icons.upgrade_rounded,
                color: AppColors.accent, size: 20),
            title: Text(
              AppStrings.t('upgrade_pro', locale),
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.accent),
            ),
            onTap: () => showServePointPaywall(context, ref),
          ),
        // Customer Center (manage subscription / cancel)
        if (isPro && isRevenueCatSupported)
          ListTile(
            leading: const Icon(Icons.manage_accounts_outlined,
                color: AppColors.textSecondary, size: 20),
            title: Text(
              AppStrings.t('manage_subscription', locale),
              style: const TextStyle(
                  fontSize: 14, color: AppColors.textPrimary),
            ),
            trailing: const Icon(Icons.arrow_forward_ios,
                size: 14, color: AppColors.textMuted),
            onTap: () async {
              await RevenueCatUI.presentCustomerCenter();
              await ref.read(subscriptionProvider.notifier).refresh();
            },
          ),
        // Restore purchases
        if (isRevenueCatSupported)
          ListTile(
            leading: const Icon(Icons.restore_rounded,
                color: AppColors.textSecondary, size: 20),
            title: Text(
              AppStrings.t('restore_purchases', locale),
              style: const TextStyle(
                  fontSize: 14, color: AppColors.textPrimary),
            ),
            onTap: () async {
              final ok =
                  await ref.read(subscriptionProvider.notifier).restore();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(ok
                      ? AppStrings.t('pro_restored', locale)
                      : AppStrings.t('no_subscription', locale)),
                  backgroundColor:
                      ok ? AppColors.accentGreen : AppColors.stockCritical,
                  behavior: SnackBarBehavior.floating,
                ));
              }
            },
          ),
      ],
    );
  }
}

// ─── Navigation Tile ──────────────────────────────────────────────────────────

class _NavTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _NavTile({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.textSecondary, size: 20),
      title: Text(label,
          style: const TextStyle(
              fontSize: 14, color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
      trailing: const Icon(Icons.arrow_forward_ios,
          size: 14, color: AppColors.textMuted),
      onTap: onTap,
    );
  }
}
