import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_message.dart';
import 'firebase_options.dart';
import 'proxy_probe_stub.dart'
    if (dart.library.io) 'proxy_probe_io.dart'
    as proxy_probe;

const _defaultMaintenanceMessage =
    'برنامه موقتاً غیرفعال است. لطفاً بعداً دوباره تلاش کن.';
final ValueNotifier<bool> _remoteAppEnabled = ValueNotifier<bool>(true);
final ValueNotifier<String> _remoteMaintenanceMessage = ValueNotifier<String>(
  _defaultMaintenanceMessage,
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initializeRemoteConfig();
  runApp(const MyApp());
}

Future<void> _initializeRemoteConfig() async {
  if (!kIsWeb && defaultTargetPlatform != TargetPlatform.android) return;
  try {
    if (kIsWeb) {
      await Firebase.initializeApp(options: firebaseWebOptions);
    } else {
      await Firebase.initializeApp();
    }
    final config = FirebaseRemoteConfig.instance;
    await config.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 5),
        minimumFetchInterval: kIsWeb
            ? const Duration(minutes: 15)
            : const Duration(hours: 1),
      ),
    );
    await config.setDefaults(const {
      'app_enabled': true,
      'maintenance_message': _defaultMaintenanceMessage,
    });

    void applyValues() {
      _remoteAppEnabled.value = config.getBool('app_enabled');
      final message = config.getString('maintenance_message').trim();
      _remoteMaintenanceMessage.value = message.isEmpty
          ? _defaultMaintenanceMessage
          : message;
    }

    applyValues();
    if (!kIsWeb) {
      config.onConfigUpdated.listen((_) async {
        try {
          await config.activate();
          applyValues();
        } on Object catch (error) {
          debugPrint('Remote Config activation failed: $error');
        }
      });
    } else {
      Timer.periodic(const Duration(minutes: 15), (_) async {
        try {
          await config.fetchAndActivate();
          applyValues();
        } on Object catch (error) {
          debugPrint('Web Remote Config refresh failed: $error');
        }
      });
    }

    try {
      await config.fetchAndActivate().timeout(const Duration(seconds: 5));
      applyValues();
    } on TimeoutException {
      debugPrint('Remote Config fetch timed out; using cached settings.');
    } on Object catch (error) {
      debugPrint('Remote Config fetch failed; using cached settings: $error');
    }
  } on Object catch (error) {
    debugPrint('Firebase initialization failed: $error');
  }
}

const green = Color(0xFF17A881);
const ink = Color(0xFF132321);
const muted = Color(0xFF73817E);
const canvas = Color(0xFFF4F7F5);
const _bushcraftInviteUrl = 'https://t.me/+m38m2ZTa19dmMmI0';
const _appDownloadUrl =
    'https://github.com/balakhial/proxy_finder/releases/latest/download/proxy-finder.apk';

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'پروکسی‌یاب',
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: green),
      scaffoldBackgroundColor: canvas,
    ),
    builder: (context, child) =>
        Directionality(textDirection: TextDirection.rtl, child: child!),
    home: ValueListenableBuilder<bool>(
      valueListenable: _remoteAppEnabled,
      builder: (context, enabled, _) =>
          enabled ? const HomePage() : const MaintenancePage(),
    ),
  );
}

class MaintenancePage extends StatelessWidget {
  const MaintenancePage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: canvas,
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF0E8),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.pause_circle_outline_rounded,
                    color: Color(0xFFD16A53),
                    size: 34,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'پروکسی‌یاب موقتاً غیرفعال است',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                ValueListenableBuilder<String>(
                  valueListenable: _remoteMaintenanceMessage,
                  builder: (context, message, _) => Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: muted,
                      height: 1.7,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class ProxyEntry {
  ProxyEntry(this.server, this.port, this.secret, this.link);
  final String server;
  final int port;
  final String secret;
  final String link;
  int? latencyMs;
  bool checking = false;
  bool online = false;
  bool checked = false;
  String get id => server + ':' + port.toString();
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<ProxyEntry> proxies = [];
  final Set<String> saved = {};
  bool scanning = false;
  bool loadingList = false;
  int tab = 0;
  final TextEditingController _messageController = TextEditingController();

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  List<ProxyEntry> get visible {
    final list = tab == 1
        ? proxies.where((p) => saved.contains(p.id)).toList()
        : List<ProxyEntry>.from(proxies);
    list.sort((a, b) {
      if (a.online != b.online) return a.online ? -1 : 1;
      if (a.latencyMs == null) return 1;
      if (b.latencyMs == null) return -1;
      return a.latencyMs!.compareTo(b.latencyMs!);
    });
    return list;
  }

  void message(String text, {AppMessageType type = AppMessageType.info}) {
    AppMessage.show(context, message: text, type: type);
  }

  Future<void> shareContent({
    required String text,
    required String subject,
    required String fallbackMessage,
  }) async {
    try {
      await SharePlus.instance.share(ShareParams(text: text, subject: subject));
    } on Object {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) message(fallbackMessage, type: AppMessageType.info);
    }
  }

  Future<void> shareProxy(ProxyEntry p) => shareContent(
    text: 'پراکسی تلگرام ${p.server}:${p.port}\n${p.link}',
    subject: 'اشتراک پراکسی تلگرام',
    fallbackMessage: 'لینک پراکسی کپی شد.',
  );

  Future<void> shareApp() => shareContent(
    text:
        'پروکسی‌یاب؛ دریافت و بررسی پراکسی‌های تلگرام\nدانلود آخرین نسخه:\n$_appDownloadUrl',
    subject: 'دانلود برنامهٔ پروکسی‌یاب',
    fallbackMessage: 'لینک دانلود برنامه کپی شد.',
  );

  ProxyEntry? parse(String value) {
    try {
      var text = value.trim();
      if (text.startsWith('tg://')) {
        text = text.replaceFirst('tg://', 'https://t.me/');
      }
      final uri = Uri.parse(text);
      const hosts = {
        't.me',
        'www.t.me',
        'telegram.me',
        'www.telegram.me',
        'telegram.dog',
      };
      if (!hosts.contains(uri.host.toLowerCase()) ||
          uri.path.toLowerCase() != '/proxy')
        return null;
      final q = uri.queryParameters;
      final server = q['server']?.trim();
      final port = int.tryParse(q['port'] ?? '');
      final secret = q['secret']?.trim();
      if (server == null ||
          server.isEmpty ||
          port == null ||
          port < 1 ||
          port > 65535 ||
          secret == null ||
          secret.isEmpty)
        return null;
      final link = Uri.https('t.me', '/proxy', {
        'server': server,
        'port': port.toString(),
        'secret': secret,
      }).toString();
      return ProxyEntry(server, port, secret, link);
    } catch (_) {
      return null;
    }
  }

  Future<void> fetchPublicList() async {
    if (loadingList || scanning) return;
    setState(() => loadingList = true);
    final client = http.Client();
    var shouldScan = false;
    try {
      final response = await client
          .get(Uri.parse('https://iwizard7.github.io/MTProxy_list/best.txt'))
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }
      final body = utf8.decode(response.bodyBytes);
      var added = 0;
      for (final line in body.split(RegExp(r'[\r\n]+')).take(50)) {
        final p = parse(line.trim());
        if (p != null && !proxies.any((old) => old.id == p.id)) {
          proxies.add(p);
          added++;
        }
      }
      if (!mounted) return;
      setState(() {});
      if (proxies.isEmpty) {
        message(
          'فهرست دریافت شد، اما پراکسی معتبری در آن نبود.',
          type: AppMessageType.warning,
        );
      } else if (kIsWeb) {
        message(
          'فهرست دریافت شد؛ مرورگر نمی‌تواند پینگ مستقیم پراکسی‌ها را بسنجد.',
          type: AppMessageType.warning,
        );
      } else {
        final detail = added == 0
            ? 'پراکسی تازه‌ای نبود؛ '
            : '$added پراکسی تازه دریافت شد؛ ';
        message('${detail}بررسی ${proxies.length} مورد شروع می‌شود.');
        shouldScan = true;
      }
    } on Object {
      if (mounted)
        message(
          'دریافت فهرست ممکن نشد؛ اتصال اینترنت را بررسی کنید.',
          type: AppMessageType.error,
        );
    } finally {
      client.close();
      if (mounted) setState(() => loadingList = false);
    }
    if (mounted && shouldScan) await scan();
  }

  Future<void> _probe(ProxyEntry p) async {
    final latency = await proxy_probe.probeProxy(p.server, p.port);
    p.checking = false;
    p.checked = true;
    p.online = latency != null;
    p.latencyMs = latency;
  }

  Future<void> scan() async {
    if (scanning) return;
    if (proxies.isEmpty) return;
    if (kIsWeb) {
      message(
        'سنجش اتصال در نسخهٔ وب پشتیبانی نمی‌شود.',
        type: AppMessageType.warning,
      );
      return;
    }
    setState(() {
      scanning = true;
      for (final p in proxies) {
        p.checking = true;
        p.latencyMs = null;
      }
    });
    for (var offset = 0; offset < proxies.length; offset += 6) {
      final batch = proxies.skip(offset).take(6).toList();
      await Future.wait(batch.map(_probe));
      if (!mounted) return;
      setState(() {});
    }
    if (!mounted) return;
    setState(() => scanning = false);
    final onlineCount = proxies.where((p) => p.online).length;
    message(
      'بررسی تمام شد؛ $onlineCount سرور پاسخ داد.',
      type: onlineCount > 0 ? AppMessageType.success : AppMessageType.warning,
    );
  }

  Future<void> openTelegram(ProxyEntry p) async {
    final uri = kIsWeb
        ? Uri.parse(p.link)
        : Uri(
            scheme: 'tg',
            host: 'proxy',
            queryParameters: {
              'server': p.server,
              'port': p.port.toString(),
              'secret': p.secret,
            },
          );
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        await Clipboard.setData(ClipboardData(text: p.link));
        message(
          'تلگرام باز نشد؛ لینک پراکسی کپی شد.',
          type: AppMessageType.warning,
        );
      }
    } on Object {
      if (mounted) {
        await Clipboard.setData(ClipboardData(text: p.link));
        message(
          'تلگرام باز نشد؛ لینک پراکسی کپی شد.',
          type: AppMessageType.warning,
        );
      }
    }
  }

  Widget proxyCard(ProxyEntry p) {
    final isSaved = saved.contains(p.id);
    final color = p.checking
        ? green
        : p.online
        ? const Color(0xFF169B67)
        : !p.checked
        ? muted
        : const Color(0xFFD94B45);
    final pingColor = p.checking || !p.checked
        ? muted
        : !p.online || (p.latencyMs ?? 400) >= 400
        ? const Color(0xFFD94B45)
        : p.latencyMs! < 200
        ? const Color(0xFF169B67)
        : const Color(0xFFE99520);
    final state = p.checking
        ? 'در حال بررسی'
        : p.online
        ? 'پاسخ‌گو'
        : !p.checked
        ? 'بررسی‌نشده'
        : 'در دسترس نیست';
    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8EFEC)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF7F1),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(Icons.dns_rounded, color: green, size: 19),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.server,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'پورت ' + p.port.toString(),
                      style: const TextStyle(color: muted, fontSize: 10),
                    ),
                  ],
                ),
              ),
              if (p.online && p.latencyMs != null)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 3),
                  child: Text(
                    p.latencyMs.toString() + ' ms',
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: pingColor,
                    ),
                  ),
                ),
              IconButton(
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 34,
                  height: 34,
                ),
                padding: EdgeInsets.zero,
                tooltip: isSaved ? 'حذف از ذخیره‌ها' : 'ذخیره',
                onPressed: () => setState(() {
                  if (!saved.add(p.id)) saved.remove(p.id);
                }),
                icon: Icon(
                  isSaved
                      ? Icons.bookmark_rounded
                      : Icons.bookmark_border_rounded,
                  size: 19,
                  color: isSaved ? green : muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Icon(
                p.checking
                    ? Icons.sync_rounded
                    : p.online
                    ? Icons.check_circle_outline_rounded
                    : Icons.circle_outlined,
                color: color,
                size: 14,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  state,
                  style: TextStyle(color: color, fontSize: 10),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 34,
                  height: 34,
                ),
                padding: EdgeInsets.zero,
                tooltip: 'کپی لینک',
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: p.link));
                  if (mounted) {
                    message('لینک کپی شد.', type: AppMessageType.success);
                  }
                },
                icon: const Icon(Icons.copy_rounded, size: 17),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 34,
                  height: 34,
                ),
                padding: EdgeInsets.zero,
                tooltip: 'اشتراک‌گذاری لینک',
                onPressed: () => shareProxy(p),
                icon: const Icon(Icons.share_rounded, size: 17),
              ),
              const SizedBox(width: 3),
              FilledButton.tonalIcon(
                onPressed: () => openTelegram(p),
                icon: const Icon(Icons.send_rounded, size: 14),
                label: const Text('افزودن به تلگرام'),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  minimumSize: const Size(0, 32),
                  textStyle: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Row(
        children: [
          Icon(Icons.bolt_rounded, color: green),
          SizedBox(width: 8),
          Text(
            'پروکسی‌یاب',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),
        ],
      ),
      actions: const [],
    ),
    body: SafeArea(
      top: false,
      child: tab == 0
          ? homeBody()
          : tab == 1
          ? savedBody()
          : aboutBody(),
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: tab,
      onDestinationSelected: (v) => setState(() => tab = v),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.radar_rounded),
          label: 'پیدا کردن',
        ),
        NavigationDestination(
          icon: Icon(Icons.bookmark_border_rounded),
          label: 'ذخیره‌شده‌ها',
        ),
        NavigationDestination(
          icon: Icon(Icons.info_outline_rounded),
          label: 'دربارهٔ سازنده',
        ),
      ],
    ),
  );

  Widget homeBody() => ListView(
    padding: const EdgeInsets.fromLTRB(16, 6, 16, 96),
    children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Color(0xFF173F38), Color(0xFF102A27)],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'سریع‌ترین پروکسی رو پیدا کن',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: loadingList || scanning ? null : fetchPublicList,
                icon: loadingList || scanning
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_download_outlined, size: 18),
                label: Text(
                  loadingList
                      ? 'در حال دریافت…'
                      : scanning
                      ? 'در حال بررسی…'
                      : kIsWeb
                      ? 'دریافت لیست پروکسی'
                      : 'دریافت لیست و اسکن پروکسی‌ها',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF72E5B9),
                  foregroundColor: const Color(0xFF10332B),
                  minimumSize: const Size.fromHeight(42),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      if (kIsWeb)
        Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFE9F3FA),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline_rounded, color: Color(0xFF5796C8)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'در نسخهٔ وب فهرست و لینک تلگرام در دسترس است؛ پینگ مستقیم به‌دلیل محدودیت مرورگر سنجیده نمی‌شود.',
                  style: TextStyle(fontSize: 11, height: 1.45),
                ),
              ),
            ],
          ),
        ),
      const SizedBox(height: 15),
      Row(
        children: [
          const Expanded(
            child: Text(
              'پراکسی‌ها',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
          ),
          Text(
            scanning
                ? 'در حال بررسی'
                : proxies.isEmpty
                ? 'آمادهٔ دریافت'
                : proxies.every((p) => !p.checked)
                ? proxies.length.toString() + ' بررسی‌نشده'
                : proxies.where((p) => p.online).length.toString() + ' پاسخ‌گو',
            style: const TextStyle(fontSize: 11, color: muted),
          ),
        ],
      ),
      const SizedBox(height: 8),
      if (visible.isEmpty)
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            children: [
              Icon(Icons.travel_explore_rounded, size: 32, color: green),
              SizedBox(height: 8),
              Text(
                'هنوز پراکسی‌ای دریافت نشده',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
              ),
              SizedBox(height: 4),
              Text(
                'برای نمایش فهرست، دکمهٔ دریافت پروکسی را بزن.',
                textAlign: TextAlign.center,
                style: TextStyle(color: muted, height: 1.5, fontSize: 11),
              ),
            ],
          ),
        )
      else
        ...visible.map(proxyCard),
    ],
  );

  Future<void> openBushcraftChannel() async {
    try {
      final opened = await launchUrl(
        Uri.parse(_bushcraftInviteUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        await Clipboard.setData(const ClipboardData(text: _bushcraftInviteUrl));
        if (mounted) {
          message('لینک دعوت کپی شد.', type: AppMessageType.info);
        }
      }
    } on Object {
      if (mounted) {
        await Clipboard.setData(const ClipboardData(text: _bushcraftInviteUrl));
        message('لینک دعوت کپی شد؛ می‌تونی آن را در تلگرام باز کنی.');
      }
    }
  }

  Widget bushcraftPromoCard() => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFE8EFEC)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          height: 148,
          child: Image.asset(
            'assets/images/bushcraft_promo.png',
            fit: BoxFit.cover,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'اگه به کمپینگ، جنگل و آموزش بوشکرفت علاقه داری داخل کانال عضو شو',
                style: TextStyle(
                  color: ink,
                  fontSize: 13,
                  height: 1.6,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: openBushcraftChannel,
                  icon: const Icon(Icons.send_rounded, size: 18),
                  label: const Text('عضویت در کانال'),
                  style: FilledButton.styleFrom(
                    backgroundColor: green,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(42),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Future<void> sendFeedback() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) {
      message('لطفاً متن پیام را بنویس.', type: AppMessageType.warning);
      return;
    }
    final uri = Uri.parse(
      'mailto:balakhial@gmail.com?subject=' +
          Uri.encodeComponent('پیام از پروکسی‌یاب') +
          '&body=' +
          Uri.encodeComponent(text),
    );
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (opened && mounted) {
        message(
          'پیام در برنامهٔ ایمیل آماده شد؛ ارسال را تأیید کن.',
          type: AppMessageType.info,
        );
      } else if (mounted) {
        message(
          'برنامهٔ ایمیلی برای ارسال پیدا نشد.',
          type: AppMessageType.error,
        );
      }
    } on Object {
      if (mounted) {
        message(
          'برنامهٔ ایمیلی برای ارسال پیدا نشد.',
          type: AppMessageType.error,
        );
      }
    }
  }

  Widget aboutBody() => ListView(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
    children: [
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF173F38),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'دربارهٔ پروکسی‌یاب',
              style: TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE8EFEC)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'حمایت از سازنده',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
            const SizedBox(height: 8),
            const Text(
              'اگر این برنامه برات مفید بود، می‌تونی از سازنده حمایت کنی.',
              style: TextStyle(color: muted, fontSize: 12, height: 1.6),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.credit_card_rounded, color: green),
                const SizedBox(width: 8),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '6221-0612-3404-0006',
                        textDirection: TextDirection.ltr,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'کپی شماره کارت',
                  onPressed: () async {
                    await Clipboard.setData(
                      const ClipboardData(text: '6221061234040006'),
                    );
                    if (mounted) {
                      message(
                        'شمارهٔ کارت کپی شد.',
                        type: AppMessageType.success,
                      );
                    }
                  },
                  icon: const Icon(Icons.copy_rounded),
                ),
              ],
            ),
            const Divider(height: 18),
            const Row(
              children: [
                Icon(Icons.send_rounded, color: green, size: 19),
                SizedBox(width: 8),
                Text('تلگرام:', style: TextStyle(fontWeight: FontWeight.w700)),
                SizedBox(width: 4),
                Text(
                  '@balakhial',
                  textDirection: TextDirection.ltr,
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE8EFEC)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'اشتراک‌گذاری برنامه',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
            const SizedBox(height: 8),
            const Text(
              'لینک دانلود آخرین نسخه را برای دوستانت بفرست.',
              style: TextStyle(color: muted, fontSize: 12, height: 1.6),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: shareApp,
                icon: const Icon(Icons.share_rounded),
                label: const Text('ارسال برنامه برای دیگران'),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      bushcraftPromoCard(),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE8EFEC)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ارسال پیام',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),

            const SizedBox(height: 12),
            TextField(
              controller: _messageController,
              minLines: 3,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'پیامت را بنویس…',
                filled: true,
                fillColor: canvas,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: sendFeedback,
                icon: const Icon(Icons.email_outlined),
                label: const Text('ادامه در برنامهٔ ایمیل'),
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget savedBody() => visible.isEmpty
      ? const Center(child: Text('هنوز موردی ذخیره نشده'))
      : ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('ذخیره‌شده‌ها'),
            const SizedBox(height: 12),
            ...visible.map(proxyCard),
          ],
        );
}
