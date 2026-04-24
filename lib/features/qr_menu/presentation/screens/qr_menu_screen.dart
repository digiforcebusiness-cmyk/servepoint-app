import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/providers/app_providers.dart';

// ─── Published menu state ─────────────────────────────────────────────────────

class _PublishedState {
  final bool isPublished;
  final DateTime? lastPublished;
  final int productCount;
  final int categoryCount;

  const _PublishedState({
    this.isPublished = false,
    this.lastPublished,
    this.productCount = 0,
    this.categoryCount = 0,
  });
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class QrMenuScreen extends ConsumerStatefulWidget {
  const QrMenuScreen({super.key});

  @override
  ConsumerState<QrMenuScreen> createState() => _QrMenuScreenState();
}

class _QrMenuScreenState extends ConsumerState<QrMenuScreen> {
  bool _publishing = false;
  _PublishedState _published = const _PublishedState();

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  String get _menuUrl {
    final uid = _uid;
    if (uid == null) return '';
    return 'https://www.servepointpos.com/menu.html?uid=$uid';
  }

  @override
  void initState() {
    super.initState();
    _checkExistingMenu();
  }

  Future<void> _checkExistingMenu() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('public_menus')
          .doc(uid)
          .get();
      if (doc.exists && mounted) {
        final data = doc.data()!;
        final cats = (data['categories'] as List?)?.length ?? 0;
        int products = 0;
        for (final cat in (data['categories'] as List? ?? [])) {
          products += ((cat as Map)['products'] as List?)?.length ?? 0;
        }
        setState(() {
          _published = _PublishedState(
            isPublished: true,
            lastPublished: (data['publishedAt'] as Timestamp?)?.toDate(),
            productCount: products,
            categoryCount: cats,
          );
        });
      }
    } catch (_) {}
  }

  Future<void> _publishMenu() async {
    final uid = _uid;
    if (uid == null) return;
    setState(() => _publishing = true);

    try {
      final db = ref.read(appDatabaseProvider);
      final branding = await ref.read(brandingProvider.future);
      final currency = CurrencyFormatter.currentCurrency;

      final allCategories = await db.getAllCategories();
      final allProducts = await db.getAllProducts();

      // Group available products by category
      final productsByCategory = <int, List<Product>>{};
      for (final p in allProducts) {
        if (!p.isAvailable) continue;
        productsByCategory.putIfAbsent(p.categoryId, () => []).add(p);
      }

      final categoriesData = <Map<String, dynamic>>[];
      int totalProducts = 0;
      for (final cat in allCategories) {
        final catProducts = productsByCategory[cat.id] ?? [];
        if (catProducts.isEmpty) continue;
        totalProducts += catProducts.length;
        categoriesData.add({
          'id': cat.id,
          'nameFr': cat.nameFr,
          'nameAr': cat.nameAr,
          'products': catProducts.map((p) => {
            'nameFr': p.nameFr,
            'nameAr': p.nameAr,
            'price': p.price,
          }).toList(),
        });
      }

      await FirebaseFirestore.instance
          .collection('public_menus')
          .doc(uid)
          .set({
        'storeName': branding.storeName,
        'currency': currency,
        'publishedAt': FieldValue.serverTimestamp(),
        'categories': categoriesData,
      });

      if (mounted) {
        setState(() {
          _published = _PublishedState(
            isPublished: true,
            lastPublished: DateTime.now(),
            productCount: totalProducts,
            categoryCount: categoriesData.length,
          );
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ref.read(appLocaleProvider) == 'ar'
                  ? 'تم نشر القائمة بنجاح!'
                  : 'Menu publié avec succès!',
            ),
            backgroundColor: AppColors.accentGreen,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: $e'),
            backgroundColor: AppColors.stockCritical,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  void _copyUrl() {
    Clipboard.setData(ClipboardData(text: _menuUrl));
    final locale = ref.read(appLocaleProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(locale == 'ar' ? 'تم نسخ الرابط!' : 'Lien copié!'),
        backgroundColor: AppColors.accentGreen,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(appLocaleProvider);
    final uid = _uid;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: Text(
          locale == 'ar' ? 'قائمة QR الرقمية' : 'Menu QR Digital',
          style: TextStyle(
            fontFamily: locale == 'ar' ? kCairoFont : null,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: uid == null
          ? Center(
              child: Text(
                locale == 'ar'
                    ? 'يجب تسجيل الدخول لاستخدام هذه الميزة'
                    : 'Connectez-vous pour utiliser cette fonctionnalité',
                style: const TextStyle(color: AppColors.textMuted),
                textAlign: TextAlign.center,
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // ── QR Code ──────────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceCard,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: QrImageView(
                            data: _menuUrl,
                            version: QrVersions.auto,
                            size: 220,
                            eyeStyle: const QrEyeStyle(
                              eyeShape: QrEyeShape.square,
                              color: Color(0xFF0D2137),
                            ),
                            dataModuleStyle: const QrDataModuleStyle(
                              dataModuleShape: QrDataModuleShape.square,
                              color: Color(0xFFE94560),
                            ),
                          ),
                        ),
                        const Gap(16),
                        // URL row
                        GestureDetector(
                          onTap: _copyUrl,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.divider),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _menuUrl,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: AppColors.textSecondary,
                                      fontFamily: 'monospace',
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const Gap(8),
                                const Icon(Icons.copy,
                                    size: 14, color: AppColors.accent),
                              ],
                            ),
                          ),
                        ),
                        const Gap(12),
                        Text(
                          locale == 'ar'
                              ? 'امسح هذا الرمز لعرض قائمتك الرقمية'
                              : 'Scannez ce code pour afficher votre menu digital',
                          style: const TextStyle(
                              color: AppColors.textMuted, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  const Gap(20),

                  // ── Status ───────────────────────────────────────────────
                  if (_published.isPublished) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.accentGreen.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: AppColors.accentGreen.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle,
                              color: AppColors.accentGreen, size: 20),
                          const Gap(10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  locale == 'ar'
                                      ? '${_published.productCount} منتج في ${_published.categoryCount} فئة'
                                      : '${_published.productCount} produits dans ${_published.categoryCount} catégories',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.accentGreen,
                                  ),
                                ),
                                if (_published.lastPublished != null)
                                  Text(
                                    '${locale == 'ar' ? 'آخر نشر' : 'Dernière mise à jour'}: '
                                    '${DateFormat('dd/MM/yyyy HH:mm').format(_published.lastPublished!)}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Gap(20),
                  ],

                  // ── Publish Button ───────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _publishing ? null : _publishMenu,
                      icon: _publishing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(
                              _published.isPublished
                                  ? Icons.refresh
                                  : Icons.publish,
                              size: 18,
                            ),
                      label: Text(
                        _publishing
                            ? (locale == 'ar' ? 'جاري النشر...' : 'Publication...')
                            : _published.isPublished
                                ? (locale == 'ar'
                                    ? 'تحديث القائمة'
                                    : 'Mettre à jour le menu')
                                : (locale == 'ar'
                                    ? 'نشر القائمة'
                                    : 'Publier le menu'),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const Gap(12),
                  Text(
                    locale == 'ar'
                        ? 'يقوم النشر بمزامنة جميع منتجاتك وفئاتك المتاحة مع قائمتك الرقمية عبر الإنترنت'
                        : 'La publication synchronise tous vos produits et catégories disponibles avec votre menu digital en ligne',
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 11),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
    );
  }
}
