import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../appcoins_iap_provider.dart';
import '../subscription_provider.dart';
import '../subscription_service.dart';
import '../windows_iap_provider.dart';

// ─── Present Paywall ──────────────────────────────────────────────────────────

/// Shows the paywall for the current platform:
/// - Windows  → Microsoft Store IAP dialog
/// - Android / iOS / macOS → RevenueCat paywall
/// Returns true if the user successfully purchased or restored Pro.
Future<bool> showServePointPaywall(BuildContext context, WidgetRef ref) async {
  // ── Windows: Microsoft Store IAP ─────────────────────────────────────────
  if (!kIsWeb && Platform.isWindows) {
    await showDialog<void>(
      context: context,
      builder: (_) => const _WindowsPaywallDialog(),
    );
    // isPro is updated automatically by the purchase stream — no restore() call
    // here, which would flash the AppGate through loading→OnboardingScreen(page 0).
    return ref.read(windowsIsProProvider);
  }

  // ── iOS: Aptoide AppCoins IAP ────────────────────────────────────────────
  if (!kIsWeb && Platform.isIOS) {
    await showDialog<void>(
      context: context,
      builder: (_) => const _AppCoinsPaywallDialog(),
    );
    return ref.read(appCoinsIsProProvider);
  }

  if (!isRevenueCatSupported) {
    await showDialog<void>(
      context: context,
      builder: (_) => const _UnsupportedPlatformDialog(),
    );
    return false;
  }

  // ── 1. Try the RevenueCat paywall UI first ────────────────────────────────
  PaywallResult? uiResult;
  try {
    uiResult = await RevenueCatUI.presentPaywall();
  } catch (e) {
    debugPrint('[RevenueCat] presentPaywall error: $e');
    uiResult = PaywallResult.error;
  }

  switch (uiResult) {
    case PaywallResult.purchased:
    case PaywallResult.restored:
      await ref.read(subscriptionProvider.notifier).refresh();
      return true;

    case PaywallResult.cancelled:
      // User explicitly closed the paywall — do nothing.
      return false;

    case PaywallResult.notPresented:
    case PaywallResult.error:
      // No paywall template configured in dashboard, or SDK error.
      // Fall through to the direct purchase dialog below.
      break;
  }

  // ── 2. Fallback: fetch offerings and purchase directly ────────────────────
  if (!context.mounted) return false;
  final purchased = await _showDirectPurchaseDialog(context, ref);
  await ref.read(subscriptionProvider.notifier).refresh();
  return purchased;
}

/// Fetches the current offering from RevenueCat and shows a simple purchase
/// dialog for users to pick and pay for a package directly.
Future<bool> _showDirectPurchaseDialog(
    BuildContext context, WidgetRef ref) async {
  // Fetch offerings
  Offerings? offerings;
  try {
    offerings = await Purchases.getOfferings();
  } catch (e) {
    debugPrint('[RevenueCat] getOfferings error: $e');
  }

  final packages = offerings?.current?.availablePackages ?? [];

  if (packages.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Aucune offre disponible pour le moment. Réessayez plus tard.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    return false;
  }

  // Show package selection dialog
  if (!context.mounted) return false;
  final Package? chosen = await showDialog<Package>(
    context: context,
    builder: (_) => _PackageSelectionDialog(packages: packages),
  );
  if (chosen == null) return false;

  // Purchase chosen package
  try {
    final result = await Purchases.purchase(PurchaseParams.package(chosen));
    return hasProAccess(result.customerInfo);
  } on PlatformException catch (e) {
    final code = PurchasesErrorHelper.getErrorCode(e);
    if (code == PurchasesErrorCode.purchaseCancelledError) return false;
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur: ${e.message ?? code.name}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    return false;
  } catch (e) {
    debugPrint('[RevenueCat] purchasePackage error: $e');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Une erreur inattendue est survenue.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    return false;
  }
}

// ─── Package Selection Dialog ─────────────────────────────────────────────────

class _PackageSelectionDialog extends StatelessWidget {
  final List<Package> packages;
  const _PackageSelectionDialog({required this.packages});

  String _label(Package p) {
    switch (p.packageType) {
      case PackageType.monthly:
        return 'Mensuel';
      case PackageType.annual:
        return 'Annuel';
      case PackageType.weekly:
        return 'Hebdomadaire';
      case PackageType.lifetime:
        return 'À vie';
      default:
        return p.identifier;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.headerDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.workspace_premium_rounded,
                  color: AppColors.accentAmber, size: 22),
              SizedBox(width: 8),
              Text(
                'ServePoint Pro',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          SizedBox(height: 4),
          Text(
            'Choisissez votre abonnement',
            style: TextStyle(
              color: Colors.white60,
              fontSize: 13,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: packages.map((pkg) {
          final price = pkg.storeProduct.priceString;
          final label = _label(pkg);
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              onTap: () => Navigator.pop(context, pkg),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: AppColors.accent.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          Text(
                            pkg.storeProduct.description.isNotEmpty
                                ? pkg.storeProduct.description
                                : 'Accès complet à ServePoint Pro',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                            maxLines: 2,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        price,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            'Annuler',
            style: TextStyle(color: Colors.white38),
          ),
        ),
      ],
    );
  }
}

// ─── Windows Microsoft Store Paywall ─────────────────────────────────────────

class _WindowsPaywallDialog extends ConsumerStatefulWidget {
  const _WindowsPaywallDialog();

  @override
  ConsumerState<_WindowsPaywallDialog> createState() =>
      _WindowsPaywallDialogState();
}

class _WindowsPaywallDialogState extends ConsumerState<_WindowsPaywallDialog> {
  String? _monthlyPriceString;
  String? _lifetimePriceString;
  bool _loadingMonthly = false;
  bool _loadingLifetime = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final service = ref.read(windowsIAPProvider.notifier).service;
      if (service == null) return;
      final monthly = await service.fetchPriceString();
      final lifetime = await service.fetchLifetimePriceString();
      if (!mounted) return;
      setState(() {
        // The Microsoft Store returns "$0.00" (and similar) for add-ons
        // that aren't actually for sale yet (still in certification,
        // paused, or not visible to this account). Treat that as "no
        // price available" so the hardcoded fallback shows instead.
        _monthlyPriceString = _usablePrice(monthly);
        _lifetimePriceString = _usablePrice(lifetime);
      });
    });
  }

  Future<void> _buyMonthly() async {
    if (_loadingMonthly) return;
    setState(() => _loadingMonthly = true);
    try {
      await ref.read(windowsIAPProvider.notifier).purchase();
    } finally {
      if (mounted) setState(() => _loadingMonthly = false);
    }
  }

  Future<void> _buyLifetime() async {
    if (_loadingLifetime) return;
    setState(() => _loadingLifetime = true);
    try {
      await ref.read(windowsIAPProvider.notifier).purchaseLifetime();
    } finally {
      if (mounted) setState(() => _loadingLifetime = false);
    }
  }

  Future<void> _restore() async {
    await ref.read(windowsIAPProvider.notifier).silentRestore();
    if (mounted) {
      final isPro = ref.read(windowsIsProProvider);
      if (isPro) {
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No active subscription found.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Auto-close the dialog as soon as the purchase stream confirms Pro.
    ref.listen<bool>(windowsIsProProvider, (_, isPro) {
      if (isPro && mounted) Navigator.pop(context);
    });

    return AlertDialog(
      backgroundColor: AppColors.headerDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(children: [
        Icon(Icons.workspace_premium_rounded,
            color: AppColors.accentAmber, size: 22),
        SizedBox(width: 8),
        Text('ServePoint Pro',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 18)),
      ]),
      content: SizedBox(
        // AlertDialog on desktop doesn't bound horizontal width by default,
        // so a Row with Expanded children collapses unpredictably. Pin the
        // dialog content to a width that comfortably fits two cards.
        width: 580,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _PaywallCard(
                    title: 'Monthly',
                    price: _monthlyPriceString ?? '\$4.99',
                    period: '/ month',
                    bullets: const [
                      'Auto-renews',
                      'Cancel anytime in Microsoft Store',
                      'All Pro features',
                    ],
                    ctaLabel: 'Subscribe',
                    loading: _loadingMonthly,
                    onPressed: _buyMonthly,
                    highlighted: false,
                  )),
                  const SizedBox(width: 14),
                  Expanded(child: _PaywallCard(
                    title: 'Lifetime',
                    price: _lifetimePriceString ?? '\$99.99',
                    period: 'one-time',
                    bullets: const [
                      'Pay once, own forever',
                      'No subscription, no renewals',
                      'Save ≈ 67% vs 12 months',
                    ],
                    ctaLabel: 'Get lifetime',
                    loading: _loadingLifetime,
                    onPressed: _buyLifetime,
                    highlighted: true,
                    badge: 'Best value',
                  )),
                ],
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: _restore,
                child: const Text('Restore purchase',
                    style: TextStyle(color: Colors.white54)),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel',
              style: TextStyle(color: Colors.white38)),
        ),
      ],
    );
  }
}

/// Returns the price string unchanged if it represents a real non-zero
/// price, or `null` otherwise so the caller can fall back to a hardcoded
/// display value. Shared by the Windows and iOS paywall dialogs.
String? _usablePrice(String? s) {
  if (s == null) return null;
  final trimmed = s.trim();
  if (trimmed.isEmpty) return null;
  // Match prices that read as zero: "0.00", "0,00", "$0.00", "0", etc.
  final digitsAndSeparators = trimmed.replaceAll(RegExp(r'[^0-9.,]'), '');
  final hasNonZero = RegExp(r'[1-9]').hasMatch(digitsAndSeparators);
  if (!hasNonZero) return null;
  return trimmed;
}

// ─── iOS AppCoins Paywall (lifetime only) ─────────────────────────────────────

class _AppCoinsPaywallDialog extends ConsumerStatefulWidget {
  const _AppCoinsPaywallDialog();

  @override
  ConsumerState<_AppCoinsPaywallDialog> createState() =>
      _AppCoinsPaywallDialogState();
}

class _AppCoinsPaywallDialogState
    extends ConsumerState<_AppCoinsPaywallDialog> {
  String? _priceString;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final service = ref.read(appCoinsIapProvider.notifier).service;
      if (service == null) return;
      final price = await service.fetchLifetimePriceString();
      if (!mounted) return;
      setState(() => _priceString = _usablePrice(price));
    });
  }

  Future<void> _buy() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await ref.read(appCoinsIapProvider.notifier).purchaseLifetime();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _restore() async {
    await ref.read(appCoinsIapProvider.notifier).silentRestore();
    if (!mounted) return;
    if (ref.read(appCoinsIsProProvider)) {
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No previous purchase found.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(appCoinsIsProProvider, (_, isPro) {
      if (isPro && mounted) Navigator.pop(context);
    });

    return AlertDialog(
      backgroundColor: AppColors.headerDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(children: [
        Icon(Icons.workspace_premium_rounded,
            color: AppColors.accentAmber, size: 22),
        SizedBox(width: 8),
        Text('ServePoint Pro',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 18)),
      ]),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            _PaywallCard(
              title: 'Lifetime',
              price: _priceString ?? '\$99',
              period: 'one-time',
              bullets: const [
                'Pay once, own forever',
                'No subscription, no renewals',
                'All Pro features',
              ],
              ctaLabel: 'Get lifetime',
              loading: _loading,
              onPressed: _buy,
              highlighted: true,
              badge: 'Best value',
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: _restore,
                child: const Text('Restore purchase',
                    style: TextStyle(color: Colors.white54)),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel',
              style: TextStyle(color: Colors.white38)),
        ),
      ],
    );
  }
}

// ─── Unsupported Platform Dialog ──────────────────────────────────────────────

class _UnsupportedPlatformDialog extends StatelessWidget {
  const _UnsupportedPlatformDialog();

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return AlertDialog(
      backgroundColor: c.surfaceCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.star_rounded, color: AppColors.accentAmber),
          SizedBox(width: 10),
          Text(
            'ServePoint Pro',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
      content: Text(
        'Subscriptions are managed on mobile (Android / iOS).\n\n'
        'On this device, all Pro features are enabled automatically.',
        style: TextStyle(color: c.textSecondary),
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: Colors.white,
          ),
          child: const Text('OK'),
        ),
      ],
    );
  }
}

// ─── Subscription Status Button ───────────────────────────────────────────────

/// A compact chip/button that shows Pro status and opens the paywall when tapped.
class SubscriptionStatusChip extends ConsumerWidget {
  const SubscriptionStatusChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPro = ref.watch(isProProvider);
    final expiry = ref.watch(proExpiryProvider);

    if (isPro) {
      return GestureDetector(
        onTap: () => _openCustomerCenter(context, ref),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFFB347), Color(0xFFFFCC02)],
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.star_rounded, size: 14, color: Colors.white),
              const SizedBox(width: 4),
              Text(
                expiry != null
                    ? 'Pro · ${_formatExpiry(expiry)}'
                    : 'Pro',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Not Pro — show upgrade button
    return GestureDetector(
      onTap: () => showServePointPaywall(context, ref),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.star_outline_rounded, size: 14, color: AppColors.accent),
            SizedBox(width: 4),
            Text(
              'Upgrade Pro',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openCustomerCenter(BuildContext context, WidgetRef ref) async {
    if (!kIsWeb && Platform.isWindows) {
      final c = AppColors.of(context);
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: c.surfaceCard,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(children: [
            Icon(Icons.star_rounded, color: AppColors.accentAmber),
            SizedBox(width: 10),
            Text('ServePoint Pro',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ]),
          content: Text(
            'To manage or cancel your subscription, open the Microsoft Store '
            'app → Library → Subscriptions → ServePoint POS.',
            style: TextStyle(color: c.textSecondary),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    if (!isRevenueCatSupported) return;
    await RevenueCatUI.presentCustomerCenter();
    await ref.read(subscriptionProvider.notifier).refresh();
  }

  String _formatExpiry(DateTime dt) {
    final diff = dt.difference(DateTime.now()).inDays;
    if (diff <= 0) return 'expiré';
    if (diff == 1) return '1j restant';
    return '${diff}j';
  }
}

// ─── Pro Gate Widget ──────────────────────────────────────────────────────────

/// Wraps [child] — shows it only when Pro is active, otherwise shows an upgrade prompt.
class ProGate extends ConsumerWidget {
  final Widget child;
  final String? featureName;

  const ProGate({super.key, required this.child, this.featureName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPro = ref.watch(isProProvider);

    if (isPro) return child;

    return _ProLockedOverlay(
      featureName: featureName,
      onUpgrade: () => showServePointPaywall(context, ref),
    );
  }
}

class _ProLockedOverlay extends StatelessWidget {
  final String? featureName;
  final VoidCallback onUpgrade;

  const _ProLockedOverlay({this.featureName, required this.onUpgrade});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_outline_rounded,
              size: 48, color: c.textMuted),
          const SizedBox(height: 16),
          Text(
            featureName != null
                ? '$featureName est réservé à ServePoint Pro'
                : 'Fonctionnalité réservée à ServePoint Pro',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: c.textSecondary,
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: onUpgrade,
            icon: const Icon(Icons.star_rounded, size: 18),
            label: const Text('Passer à Pro'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaywallCard extends StatelessWidget {
  final String title;
  final String price;
  final String period;
  final List<String> bullets;
  final String ctaLabel;
  final bool loading;
  final VoidCallback onPressed;
  final bool highlighted;
  final String? badge;

  const _PaywallCard({
    required this.title,
    required this.price,
    required this.period,
    required this.bullets,
    required this.ctaLabel,
    required this.loading,
    required this.onPressed,
    required this.highlighted,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    // Colors are hardcoded for the navy paywall dialog background
    // (AppColors.headerDark). Theme tokens would resolve to dark text on
    // the light app theme — invisible on the dialog.
    const cardBg = Color(0xFF252540);                 // slightly lighter navy
    const borderIdle = Color(0xFF3A3A55);
    const textPrimary = Colors.white;
    const textSecondary = Color(0xCCFFFFFF);          // white at ~80%
    const textMuted = Color(0x99FFFFFF);              // white at ~60%

    final card = Container(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: highlighted ? AppColors.accent : borderIdle,
          width: highlighted ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title,
              style: const TextStyle(
                color: textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              )),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(price,
                  style: const TextStyle(
                    color: textPrimary,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  )),
              const SizedBox(width: 6),
              Text(period,
                  style: const TextStyle(
                    color: textSecondary,
                    fontSize: 13,
                  )),
            ],
          ),
          const SizedBox(height: 14),
          for (final b in bullets)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check, size: 16, color: textMuted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(b,
                        style: const TextStyle(
                          color: textSecondary,
                          fontSize: 13,
                          height: 1.3,
                        )),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: loading ? null : onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    highlighted ? AppColors.accent : Colors.white,
                foregroundColor: highlighted
                    ? Colors.white
                    : const Color(0xFF1A1A2E),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
              child: loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(ctaLabel,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      )),
            ),
          ),
        ],
      ),
    );

    if (badge == null) return card;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        card,
        Positioned(
          top: -10,
          right: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              badge!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
