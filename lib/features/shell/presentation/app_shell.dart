import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../home/presentation/home_screen.dart';
import '../../trips/presentation/trips_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  var _index = 0;
  @override
  Widget build(BuildContext context) {
    final pages = [
      const HomeScreen(),
      const TripsScreen(),
      const _SettingsScreen(),
    ];
    return Scaffold(
      body: SafeArea(child: pages[_index]),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          height: 62,
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              fontSize: 11,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w700
                  : FontWeight.w500,
            ),
          ),
          iconTheme: WidgetStateProperty.all(const IconThemeData(size: 20)),
          indicatorColor: AppTheme.sand,
          indicatorShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (value) => setState(() => _index = value),
          backgroundColor: AppTheme.paper,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: '홈',
            ),
            NavigationDestination(
              icon: Icon(Icons.auto_stories_outlined),
              selectedIcon: Icon(Icons.auto_stories),
              label: '여행',
            ),
            NavigationDestination(
              icon: Icon(Icons.tune_outlined),
              selectedIcon: Icon(Icons.tune),
              label: '설정',
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsScreen extends StatelessWidget {
  const _SettingsScreen();
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(28, 48, 28, 30),
    children: [
      const Text(
        '설정',
        style: TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w700,
          letterSpacing: -1,
        ),
      ),
      const SizedBox(height: 38),
      const _SettingSection(
        title: '프라이버시',
        items: [('프라이버시 존', '장소 기록 제외 구역'), ('기본 공유 범위', '나만 보기')],
      ),
      const SizedBox(height: 34),
      const _SettingSection(
        title: '여행 기록',
        items: [
          ('위치 기록 안내', '여행 중에만 위치를 기록합니다.'),
          ('배터리 최적화 안내', '긴 여행 기록을 위해 설정을 확인하세요.'),
        ],
      ),
      const SizedBox(height: 34),
      const _SettingSection(
        title: '앱 정보',
        items: [('앱 버전', '1.0.0'), ('개인정보처리방침', '')],
      ),
    ],
  );
}

class _SettingSection extends StatelessWidget {
  const _SettingSection({required this.title, required this.items});
  final String title;
  final List<(String, String)> items;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          color: AppTheme.forest,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.3,
        ),
      ),
      const SizedBox(height: 13),
      ...items.map((item) => _SettingRow(title: item.$1, subtitle: item.$2)),
    ],
  );
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({required this.title, required this.subtitle});
  final String title, subtitle;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF68665F),
                  ),
                ),
              ],
            ],
          ),
        ),
        const Icon(Icons.chevron_right, size: 18, color: Color(0xFF68665F)),
      ],
    ),
  );
}
