import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';

import '../../../core/theme/app_theme.dart';
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
  bool _loading = false;
  String? _priceString;

  @override
  void initState() {
    super.initState();
    _loadPrice();
  }

  Future<void> _loadPrice() async {
    final service = ref.read(windowsIAPProvider.notifier).service;
    final product = await service?.fetchProProduct();
    if (mounted && product != null) {
      setState(() => _priceString = product.price);
    }
  }

  Future<void> _subscribe() async {
    final service = ref.read(windowsIAPProvider.notifier).service;
    if (service != null && !service.isStoreAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Subscription requires the Microsoft Store version of ServePoint. '
            'Please install from the Store to subscribe.',
          ),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 5),
        ),
      );
      return;
    }
    setState(() => _loading = true);
    await ref.read(windowsIAPProvider.notifier).purchase();
    // buyNonConsumable() is fire-and-forget on Windows — the result arrives
    // asynchronously via purchaseStream → windowsIsProProvider.
    // The ref.listen in build() will pop the dialog when isPro becomes true.
    // If the Store dialog was cancelled or failed, reset the loading state.
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _restore() async {
    setState(() => _loading = true);
    await ref.read(windowsIAPProvider.notifier).silentRestore();
    if (mounted) {
      final isPro = ref.read(windowsIsProProvider);
      if (isPro) {
        Navigator.pop(context);
      } else {
        setState(() => _loading = false);
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
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Unlock all Pro features on your Windows device.',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 16),
          ...[
            'Unlimited devices & real-time sync',
            'Kitchen Display System (KDS)',
            'Inventory management',
            'Sales reports & analytics',
            'Bluetooth thermal printer',
          ].map((f) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  const Icon(Icons.check_circle_rounded,
                      size: 16, color: AppColors.accentAmber),
                  const SizedBox(width: 8),
                  Text(f,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 13)),
                ]),
              )),
          const SizedBox(height: 20),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _subscribe,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  _priceString != null
                      ? 'Subscribe — $_priceString / month'
                      : 'Subscribe — \$5.00 / month',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15),
                ),
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
        ],
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
    return AlertDialog(
      backgroundColor: AppColors.surfaceCard,
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
      content: const Text(
        'Subscriptions are managed on mobile (Android / iOS).\n\n'
        'On this device, all Pro features are enabled automatically.',
        style: TextStyle(color: AppColors.textSecondary),
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
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppColors.surfaceCard,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(children: [
            Icon(Icons.star_rounded, color: AppColors.accentAmber),
            SizedBox(width: 10),
            Text('ServePoint Pro',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ]),
          content: const Text(
            'To manage or cancel your subscription, open the Microsoft Store '
            'app → Library → Subscriptions → ServePoint POS.',
            style: TextStyle(color: AppColors.textSecondary),
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
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.lock_outline_rounded,
              size: 48, color: AppColors.textMuted),
          const SizedBox(height: 16),
          Text(
            featureName != null
                ? '$featureName est réservé à ServePoint Pro'
                : 'Fonctionnalité réservée à ServePoint Pro',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
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
