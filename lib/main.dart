// Flutter 3.22+ — Material 3 — واجهة عربية RTL
// صفحة واحدة أنيقة تدعم لصق الرابط، التحقق الذكي، اختيار الصيغة والجودة،
// وتقوم بالاتصال بـ /api/download في سيرفرك ثم تحفظ الملف محليًا وتفتحه.
// المنصات المدعومة: YouTube • TikTok • Instagram • X (Twitter)

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DownloaderApp());
}

class DownloaderApp extends StatelessWidget {
  const DownloaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    final baseTheme = ThemeData(
      useMaterial3: true,
      colorSchemeSeed: const Color(0xFF10B981), // Emerald
      brightness: Brightness.dark,
      textTheme: GoogleFonts.cairoTextTheme(),
    );
    return MaterialApp(
      title: 'التحميل الفوري',
      debugShowCheckedModeBanner: false,
      theme: baseTheme,
      home: const HomePage(),
      locale: const Locale('ar'),
      localizationsDelegates: const [
        DefaultWidgetsLocalizations.delegate,
        DefaultMaterialLocalizations.delegate,
        DefaultCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ar')],
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _urlCtrl = TextEditingController();
  final _fileNameCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  // غيّرها بعنوان سيرفرك — افتراضيًا لوكال هوست.
  // على الهاتف، ضع IP جهازك على الشبكة، مثلاً: http://192.168.1.7:5000
  String apiBase = 'http://127.0.0.1:5000';

  String format = 'mp4';
  String quality = 'best';
  bool loading = false;
  double progress = 0.0; // بصري فقط (تقديري)

  static final supportedRegex = RegExp(
    r'^(https?:\/\/)?(www\.)?(youtube\.com|youtu\.be|tiktok\.com|vt\.tiktok\.com|instagram\.com|instagr\.am|twitter\.com|x\.com)\/',
    caseSensitive: false,
  );

  @override
  void dispose() {
    _urlCtrl.dispose();
    _fileNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    final t = data?.text?.trim();
    if (t != null && t.isNotEmpty) {
      setState(() => _urlCtrl.text = t);
    }
  }

  Future<void> _pickServerDialog() async {
    final ctrl = TextEditingController(text: apiBase);
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            left: 16,
            right: 16,
            top: 12,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('عنوان الخادم (API)', style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.link),
                  labelText: 'مثال: http://192.168.1.7:5000',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {
                  setState(() => apiBase = ctrl.text.trim());
                  Navigator.pop(ctx);
                },
                child: const Text('حفظ'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _submit() async {
    final url = _urlCtrl.text.trim();
    if (!supportedRegex.hasMatch(url)) {
      _showSnack('رابط غير مدعوم');
      return;
    }

    setState(() {
      loading = true;
      progress = 0.12;
    });

    try {
      // نبني الطلب
      final body = jsonEncode({
        'url': url,
        'format': format,
        'quality': quality,
        'filename': _fileNameCtrl.text.trim().isEmpty ? null : _fileNameCtrl.text.trim(),
      });

      final uri = Uri.parse('$apiBase/api/download');
      final res = await http.post(
        uri,
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        body: body,
      );

      if (res.statusCode != 200) {
        final msg = _extractError(res.body) ?? 'فشل التحميل (${res.statusCode})';
        throw Exception(msg);
      }

      // اسم الملف من الهيدر
      progress = 0.6;
      final dispo = res.headers['content-disposition'] ?? '';
      final name = _dispositionFilename(dispo) ?? _suggestNameFromUrl(url, fallback: 'download');

      final bytes = res.bodyBytes; // الملف كـ bytes
      progress = 0.8;

      // نحفظه في مجلد مؤقت داخل التطبيق
      final dir = await getApplicationDocumentsDirectory();
      final filePath = '${dir.path}/$name';
      final file = File(filePath);
      await file.writeAsBytes(bytes);

      setState(() => progress = 1.0);

      // فتح الملف مباشرة
      await OpenFilex.open(file.path);
      _showSnack('تم الحفظ: $name');
    } catch (e) {
      _showSnack(e.toString());
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  String? _extractError(String body) {
    try {
      final map = jsonDecode(body) as Map<String, dynamic>;
      return map['message']?.toString();
    } catch (_) {
      return null;
    }
  }

  String? _dispositionFilename(String dispo) {
    // يحاول استخراج filename*= أو filename=
    final re = RegExp(r"filename\*=UTF-8''([^;]+)|filename=\"?([^\"]+)\"?", caseSensitive: false);
    final m = re.firstMatch(dispo);
    if (m == null) return null;
    final raw = m.group(1) ?? m.group(2);
    if (raw == null) return null;
    try { return Uri.decodeFull(raw); } catch (_) { return raw; }
  }

  String _suggestNameFromUrl(String url, {String fallback = 'download'}) {
    try {
      final u = Uri.parse(url);
      final last = u.pathSegments.isNotEmpty ? u.pathSegments.last : fallback;
      final clean = last.replaceAll(RegExp(r'[^\w\-\.]'), '_');
      final ext = (format == 'mp3' || format == 'm4a') ? format : 'mp4';
      return clean.isEmpty ? '$fallback.$ext' : '$clean.$ext';
    } catch (_) {
      final ext = (format == 'mp3' || format == 'm4a') ? format : 'mp4';
      return '$fallback.$ext';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('التحميل الفوري'),
          centerTitle: true,
          actions: [
            IconButton(
              tooltip: 'إعدادات الخادم',
              onPressed: _pickServerDialog,
              icon: const Icon(Icons.settings_suggest_rounded),
            )
          ],
        ),
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                cs.surfaceTint.withOpacity(.08),
                cs.surface.withOpacity(.06),
                Colors.black.withOpacity(.8),
              ],
            ),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Card(
                    elevation: 0,
                    color: Colors.white.withOpacity(0.04),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    child: Padding(
                      padding: const EdgeInsets.all(18.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _Chip(text: 'YouTube'),
                              const SizedBox(width: 8),
                              _Chip(text: 'TikTok'),
                              const SizedBox(width: 8),
                              _Chip(text: 'Instagram'),
                              const SizedBox(width: 8),
                              _Chip(text: 'X'),
                            ],
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _urlCtrl,
                            keyboardType: TextInputType.url,
                            decoration: InputDecoration(
                              labelText: 'الرابط',
                              hintText: 'https://…',
                              prefixIcon: const Icon(Icons.link),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                              suffixIcon: IconButton(
                                tooltip: 'لصق',
                                onPressed: _pasteFromClipboard,
                                icon: const Icon(Icons.paste_rounded),
                              ),
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return 'أدخل الرابط';
                              if (!supportedRegex.hasMatch(v.trim())) return 'رابط غير مدعوم';
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: format,
                                  items: const [
                                    DropdownMenuItem(value: 'mp4', child: Text('MP4')),
                                    DropdownMenuItem(value: 'm4a', child: Text('M4A')),
                                    DropdownMenuItem(value: 'mp3', child: Text('MP3')),
                                    DropdownMenuItem(value: 'webm', child: Text('WEBM')),
                                  ],
                                  onChanged: (v) => setState(() => format = v ?? 'mp4'),
                                  decoration: InputDecoration(
                                    labelText: 'الصيغة',
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: quality,
                                  items: const [
                                    DropdownMenuItem(value: 'best', child: Text('أفضل')),
                                    DropdownMenuItem(value: '1080', child: Text('1080p')),
                                    DropdownMenuItem(value: '720', child: Text('720p')),
                                    DropdownMenuItem(value: '480', child: Text('480p')),
                                    DropdownMenuItem(value: 'audio', child: Text('صوت فقط')),
                                  ],
                                  onChanged: (v) => setState(() => quality = v ?? 'best'),
                                  decoration: InputDecoration(
                                    labelText: 'الجودة',
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _fileNameCtrl,
                            decoration: InputDecoration(
                              labelText: 'اسم الملف (اختياري)',
                              prefixIcon: const Icon(Icons.description_outlined),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            icon: loading
                                ? const SizedBox(
                                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.download_rounded),
                            onPressed: loading
                                ? null
                                : () {
                                    if (_formKey.currentState!.validate()) {
                                      _submit();
                                    }
                                  },
                            label: const Text('تحميل'),
                          ),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 400),
                            child: loading
                                ? Padding(
                                    key: const ValueKey('pbar'),
                                    padding: const EdgeInsets.only(top: 16.0),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: LinearProgressIndicator(
                                        value: progress.clamp(0.0, 1.0),
                                        minHeight: 8,
                                      ),
                                    ),
                                  )
                                : const SizedBox.shrink(key: ValueKey('empty')),
                          ),
                          const SizedBox(height: 6),
                          Align(
                            alignment: Alignment.center,
                            child: Text(
                              'YouTube • TikTok • Instagram • X',
                              style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.white70),
                            ),
                          )
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }
}
