import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../models/link_hub_config.dart';
import '../../../services/admin_auth_service.dart';
import '../../../services/api_service.dart';
import '../../../services/restaurant_settings_service.dart';
import '../../../services/super_admin_scope_service.dart';
import '../../../utils/restaurant_route.dart';
import '../../link_hub/link_hub_view.dart';
import '../admin_breakpoints.dart';
import 'link_hub_qr_download.dart';

/// Admin manager for the public link-in-bio hub page.
class AdminLinkHubPanel extends StatefulWidget {
  const AdminLinkHubPanel({super.key});

  @override
  State<AdminLinkHubPanel> createState() => _AdminLinkHubPanelState();
}

class _AdminLinkHubPanelState extends State<AdminLinkHubPanel> {
  final _tagline = TextEditingController();
  final _displayName = TextEditingController();
  final _accent = TextEditingController(text: '#FF6B00');
  final _background = TextEditingController(text: '#0F0F10');
  final _surface = TextEditingController(text: '#1A1A1C');
  final _textColor = TextEditingController(text: '#FFFFFF');
  final _phone = TextEditingController();
  final _appStore = TextEditingController();
  final _playStore = TextEditingController();
  final _instagram = TextEditingController();
  final _tiktok = TextEditingController();
  final _snapchat = TextEditingController();
  final _facebook = TextEditingController();
  final _website = TextEditingController();
  final _qrKey = GlobalKey();

  var _loading = true;
  var _saving = false;
  String? _error;
  String _logoUrl = '';
  String _description = '';
  String _restaurantName = '';
  String _slug = '';
  String _whatsapp = '';
  var _showMenuCta = true;
  var _showWhatsapp = true;
  var _showCall = true;
  var _showAppStore = false;
  var _showPlayStore = false;
  List<LinkHubCustomLink> _links = [];
  List<LinkHubBranch> _branches = [];

  String get _restaurantId =>
      SuperAdminScopeService.instance.effectiveRestaurantId.isNotEmpty
          ? SuperAdminScopeService.instance.effectiveRestaurantId
          : (AdminAuthService.instance.restaurantId ?? '');

  String get _publicUrl {
    if (_slug.trim().isEmpty) return '';
    return RestaurantRoute.publicLinksUrl(_slug);
  }

  LinkHubConfig get _draftHub => LinkHubConfig(
        displayName: _displayName.text.trim(),
        tagline: _tagline.text.trim(),
        accentColor: _accent.text.trim(),
        backgroundColor: _background.text.trim(),
        surfaceColor: _surface.text.trim(),
        textColor: _textColor.text.trim(),
        showMenuCta: _showMenuCta,
        showWhatsapp: _showWhatsapp,
        showCall: _showCall,
        showAppStore: _showAppStore,
        showPlayStore: _showPlayStore,
        appStoreUrl: _appStore.text.trim(),
        playStoreUrl: _playStore.text.trim(),
        phoneOverride: _phone.text.trim(),
        customLinks: List.unmodifiable(_links),
        branches: List.unmodifiable(_branches),
        social: LinkHubSocial(
          instagram: _instagram.text.trim(),
          tiktok: _tiktok.text.trim(),
          snapchat: _snapchat.text.trim(),
          facebook: _facebook.text.trim(),
          website: _website.text.trim(),
        ),
      );

  @override
  void initState() {
    super.initState();
    SuperAdminScopeService.instance.addListener(_onScopeChanged);
    _load();
  }

  @override
  void dispose() {
    SuperAdminScopeService.instance.removeListener(_onScopeChanged);
    for (final c in [
      _tagline,
      _displayName,
      _accent,
      _background,
      _surface,
      _textColor,
      _phone,
      _appStore,
      _playStore,
      _instagram,
      _tiktok,
      _snapchat,
      _facebook,
      _website,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _onScopeChanged() => _load();

  void _bump() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final settings = await RestaurantSettingsService.instance.load(
        restaurantId: _restaurantId,
      );
      final auth = AdminAuthService.instance;
      final scope = SuperAdminScopeService.instance;
      // Prefer the logged-in restaurant identity; never fall back to "first
      // public restaurant" (that was showing Molton for every tenant).
      var name = (auth.restaurantName ?? '').trim();
      if (name.isEmpty &&
          scope.selectedRestaurantName?.trim().isNotEmpty == true &&
          scope.selectedRestaurantId == _restaurantId) {
        name = scope.selectedRestaurantName!.trim();
      }
      if (name.isEmpty) name = 'المطعم';
      var slug = '';
      try {
        final fromScope = scope.restaurants
            .where((r) => r.id == _restaurantId)
            .toList();
        if (fromScope.isNotEmpty) {
          name = fromScope.first.name;
          slug = fromScope.first.slug;
        } else if (_restaurantId.isNotEmpty) {
          final public = await ApiService.instance.fetchPublicRestaurant(
            restaurantId: _restaurantId,
          );
          // Only accept a restaurant that matches this admin's tenant.
          if (public.id == _restaurantId) {
            name = public.name;
            slug = public.slug;
          }
        }
      } catch (_) {}
      if (name.trim().isEmpty) {
        name = auth.restaurantName?.trim().isNotEmpty == true
            ? auth.restaurantName!.trim()
            : 'المطعم';
      }
      final hub = settings.linkHub;
      _displayName.text =
          hub.displayName.trim().isNotEmpty ? hub.displayName : name;
      _tagline.text = hub.tagline;
      _accent.text = hub.accentColor;
      _background.text = hub.backgroundColor;
      _surface.text = hub.surfaceColor;
      _textColor.text = hub.textColor;
      _phone.text = hub.phoneOverride;
      _appStore.text = hub.appStoreUrl;
      _playStore.text = hub.playStoreUrl;
      _instagram.text = hub.social.instagram;
      _tiktok.text = hub.social.tiktok;
      _snapchat.text = hub.social.snapchat;
      _facebook.text = hub.social.facebook;
      _website.text = hub.social.website;
      if (!mounted) return;
      setState(() {
        _logoUrl = settings.logoUrl;
        _description = settings.restaurantDescription;
        _whatsapp = settings.fullWhatsappNumber;
        _restaurantName = name;
        _slug = slug.trim().toLowerCase();
        _showMenuCta = hub.showMenuCta;
        _showWhatsapp = hub.showWhatsapp;
        _showCall = hub.showCall;
        _showAppStore = hub.showAppStore;
        _showPlayStore = hub.showPlayStore;
        _links = List.of(hub.customLinks);
        _branches = List.of(hub.branches);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await RestaurantSettingsService.instance.saveLinkHub(
        linkHub: _draftHub,
        restaurantId: _restaurantId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ صفحة الروابط ومزامنتها مباشرة')),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل الحفظ: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _copyLink() async {
    final url = _publicUrl;
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أضف slug للمطعم أولاً')),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم نسخ الرابط')),
    );
  }

  Future<void> _downloadQr() async {
    final url = _publicUrl;
    if (url.isEmpty) return;
    try {
      final boundary =
          _qrKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        await downloadLinkHubQrPng(url, filename: 'almenupro-$_slug-links-qr.png');
      } else {
        final image = await boundary.toImage(pixelRatio: 4);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final data = bytes?.buffer.asUint8List();
        if (data != null) {
          await downloadBytesAsFile(
            data,
            filename: 'almenupro-$_slug-links-qr.png',
          );
        } else {
          await downloadLinkHubQrPng(
            url,
            filename: 'almenupro-$_slug-links-qr.png',
          );
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تنزيل رمز QR')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تنزيل QR: $error')),
      );
    }
  }

  void _addLink() {
    setState(() {
      _links = [
        ..._links,
        LinkHubCustomLink(
          id: 'link_${DateTime.now().millisecondsSinceEpoch}',
          title: 'رابط جديد',
          url: 'https://',
        ),
      ];
    });
  }

  void _addBranch() {
    setState(() {
      _branches = [
        ..._branches,
        LinkHubBranch(
          id: 'branch_${DateTime.now().millisecondsSinceEpoch}',
          name: 'فرع جديد',
        ),
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('إعادة المحاولة')),
          ],
        ),
      );
    }

    final wide = MediaQuery.sizeOf(context).width >= 1100;
    final editors = _buildEditors();
    final preview = _buildPreviewColumn();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 6, child: editors),
              const SizedBox(width: 16),
              Expanded(flex: 4, child: preview),
            ],
          )
        else ...[
          preview,
          const SizedBox(height: 16),
          editors,
        ],
        const SizedBox(height: 16),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_rounded),
            label: Text(_saving ? 'جارٍ الحفظ…' : 'حفظ التغييرات'),
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewColumn() {
    final url = _publicUrl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ShareCard(
          url: url,
          qrKey: _qrKey,
          onCopy: _copyLink,
          onDownloadQr: _downloadQr,
          onOpen: () async {
            final uri = Uri.tryParse(url);
            if (uri == null) return;
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          },
        ),
        const SizedBox(height: 14),
        Text(
          'معاينة مباشرة — اضغط «حفظ التغييرات» ليطابق الرابط والـ QR هذه المعاينة',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: Colors.grey.shade800,
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Container(
            width: 320,
            height: 640,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.black87, width: 8),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 24,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: LinkHubView(
              restaurantName: _restaurantName,
              slug: _slug.isEmpty ? 'demo' : _slug,
              logoUrl: _logoUrl,
              description: _description,
              hub: _draftHub,
              whatsappNumber: _whatsapp,
              restaurantPhone: _phone.text,
              compact: true,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEditors() {
    final pad = AdminBreakpoints.pagePadding(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _section(
          'الهوية والألوان',
          [
            TextField(
              controller: _displayName,
              onChanged: (_) => _bump(),
              decoration: const InputDecoration(
                labelText: 'اسم المطعم الظاهر في الصفحة',
                helperText: 'هذا الاسم يظهر في الرابط العام والـ QR بعد الحفظ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _tagline,
              onChanged: (_) => _bump(),
              decoration: const InputDecoration(
                labelText: 'نبذة قصيرة / Tagline',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _accent,
                    onChanged: (_) => _bump(),
                    decoration: const InputDecoration(
                      labelText: 'لون التمييز',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _background,
                    onChanged: (_) => _bump(),
                    decoration: const InputDecoration(
                      labelText: 'لون الخلفية',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _surface,
                    onChanged: (_) => _bump(),
                    decoration: const InputDecoration(
                      labelText: 'لون البطاقات',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _textColor,
                    onChanged: (_) => _bump(),
                    decoration: const InputDecoration(
                      labelText: 'لون الخط',
                      helperText: 'للعناوين والنصوص والأزرار',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'الشعار والوصف الأساسي يُداران من تبويب «بيانات المحل».',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ],
          pad,
        ),
        _section(
          'أزرار الإجراءات',
          [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('المنيو أونلاين'),
              value: _showMenuCta,
              onChanged: (v) => setState(() => _showMenuCta = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('واتساب'),
              value: _showWhatsapp,
              onChanged: (v) => setState(() => _showWhatsapp = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('اتصل بنا'),
              value: _showCall,
              onChanged: (v) => setState(() => _showCall = v),
            ),
            TextField(
              controller: _phone,
              onChanged: (_) => _bump(),
              decoration: const InputDecoration(
                labelText: 'رقم الاتصال (اختياري)',
                border: OutlineInputBorder(),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('زر App Store'),
              value: _showAppStore,
              onChanged: (v) => setState(() => _showAppStore = v),
            ),
            TextField(
              controller: _appStore,
              onChanged: (_) => _bump(),
              decoration: const InputDecoration(
                labelText: 'رابط App Store',
                border: OutlineInputBorder(),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('زر Google Play'),
              value: _showPlayStore,
              onChanged: (v) => setState(() => _showPlayStore = v),
            ),
            TextField(
              controller: _playStore,
              onChanged: (_) => _bump(),
              decoration: const InputDecoration(
                labelText: 'رابط Google Play',
                border: OutlineInputBorder(),
              ),
            ),
          ],
          pad,
        ),
        _section(
          'روابط مخصصة',
          [
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _links.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final item = _links.removeAt(oldIndex);
                  _links.insert(newIndex, item);
                });
              },
              itemBuilder: (context, index) {
                final link = _links[index];
                return Card(
                  key: ValueKey(link.id),
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.drag_handle_rounded),
                            const SizedBox(width: 6),
                            Expanded(
                              child: TextFormField(
                                initialValue: link.title,
                                decoration: const InputDecoration(
                                  labelText: 'العنوان',
                                  isDense: true,
                                ),
                                onChanged: (v) {
                                  _links[index] = link.copyWith(title: v);
                                  _bump();
                                },
                              ),
                            ),
                            IconButton(
                              tooltip: link.visible ? 'إخفاء' : 'إظهار',
                              onPressed: () {
                                setState(() {
                                  _links[index] =
                                      link.copyWith(visible: !link.visible);
                                });
                              },
                              icon: Icon(
                                link.visible
                                    ? Icons.visibility_rounded
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                            IconButton(
                              onPressed: () {
                                setState(() => _links.removeAt(index));
                              },
                              icon: const Icon(Icons.delete_outline_rounded),
                            ),
                          ],
                        ),
                        TextFormField(
                          initialValue: link.url,
                          decoration: const InputDecoration(
                            labelText: 'الرابط',
                            isDense: true,
                          ),
                          onChanged: (v) {
                            _links[index] = link.copyWith(url: v);
                            _bump();
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            OutlinedButton.icon(
              onPressed: _addLink,
              icon: const Icon(Icons.add_rounded),
              label: const Text('إضافة رابط'),
            ),
          ],
          pad,
        ),
        _section(
          'الفروع',
          [
            for (var i = 0; i < _branches.length; i++)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              initialValue: _branches[i].name,
                              decoration: const InputDecoration(
                                labelText: 'اسم الفرع',
                                isDense: true,
                              ),
                              onChanged: (v) {
                                _branches[i] = _branches[i].copyWith(name: v);
                                _bump();
                              },
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              setState(() {
                                _branches[i] = _branches[i]
                                    .copyWith(visible: !_branches[i].visible);
                              });
                            },
                            icon: Icon(
                              _branches[i].visible
                                  ? Icons.visibility_rounded
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              setState(() => _branches.removeAt(i));
                            },
                            icon: const Icon(Icons.delete_outline_rounded),
                          ),
                        ],
                      ),
                      TextFormField(
                        initialValue: _branches[i].address,
                        decoration: const InputDecoration(
                          labelText: 'العنوان',
                          isDense: true,
                        ),
                        onChanged: (v) {
                          _branches[i] = _branches[i].copyWith(address: v);
                          _bump();
                        },
                      ),
                      TextFormField(
                        initialValue: _branches[i].mapsUrl,
                        decoration: const InputDecoration(
                          labelText: 'رابط Google Maps',
                          isDense: true,
                        ),
                        onChanged: (v) {
                          _branches[i] = _branches[i].copyWith(mapsUrl: v);
                          _bump();
                        },
                      ),
                      TextFormField(
                        initialValue: _branches[i].phone,
                        decoration: const InputDecoration(
                          labelText: 'هاتف الفرع',
                          isDense: true,
                        ),
                        onChanged: (v) {
                          _branches[i] = _branches[i].copyWith(phone: v);
                          _bump();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            OutlinedButton.icon(
              onPressed: _addBranch,
              icon: const Icon(Icons.add_business_rounded),
              label: const Text('إضافة فرع'),
            ),
          ],
          pad,
        ),
        _section(
          'وسائل التواصل',
          [
            TextField(
              controller: _instagram,
              onChanged: (_) => _bump(),
              decoration: const InputDecoration(
                labelText: 'Instagram',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _tiktok,
              onChanged: (_) => _bump(),
              decoration: const InputDecoration(
                labelText: 'TikTok',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _snapchat,
              onChanged: (_) => _bump(),
              decoration: const InputDecoration(
                labelText: 'Snapchat',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _facebook,
              onChanged: (_) => _bump(),
              decoration: const InputDecoration(
                labelText: 'Facebook',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _website,
              onChanged: (_) => _bump(),
              decoration: const InputDecoration(
                labelText: 'Website',
                border: OutlineInputBorder(),
              ),
            ),
          ],
          pad,
        ),
      ],
    );
  }

  Widget _section(String title, List<Widget> children, double pad) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: EdgeInsets.all(pad.clamp(12, 18)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _ShareCard extends StatelessWidget {
  const _ShareCard({
    required this.url,
    required this.qrKey,
    required this.onCopy,
    required this.onDownloadQr,
    required this.onOpen,
  });

  final String url;
  final GlobalKey qrKey;
  final VoidCallback onCopy;
  final VoidCallback onDownloadQr;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF6B1124),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'رابط صفحة الروابط العام',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'بعد أي تعديل اضغط حفظ — ثم افتح الرابط أو امسح الـ QR للتأكد',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 8),
            SelectableText(
              url.isEmpty ? '— أضف slug للمطعم —' : url,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: url.isEmpty ? null : onCopy,
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('نسخ الرابط'),
                ),
                FilledButton.tonalIcon(
                  onPressed: url.isEmpty ? null : onOpen,
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('فتح الصفحة'),
                ),
                FilledButton.tonalIcon(
                  onPressed: url.isEmpty ? null : onDownloadQr,
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('تنزيل QR'),
                ),
              ],
            ),
            if (url.isNotEmpty) ...[
              const SizedBox(height: 14),
              Center(
                child: RepaintBoundary(
                  key: qrKey,
                  child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(12),
                    child: QrImageView(
                      data: url,
                      size: 180,
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: Color(0xFF6B1124),
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
