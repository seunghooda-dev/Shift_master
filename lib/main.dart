import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'desktop_image_helper.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ShiftMasterApp());
}

enum ShiftType { day, evening, night, off }
enum Team { a, b }

class _ShiftMasterTheme {
  static const Color appBackground = Color(0xFFF7F7F9);
  static const Color headerBackground = Color(0xFFE7897D);
  static const Color toolbarBackground = Color(0xFFF1F2F6);
  static const Color sheetBackground = Color(0xFFF6FBFF);
  static const Color errorBannerBackground = Color(0xFFFFF1F0);
  static const Color errorBannerForeground = Color(0xFFD92F2F);
  static const Color dayCellBorder = Color(0xFFE8E8EE);
}

class ShiftEntry {
  final ShiftType type;
  final TimeOfDay? startTime;
  final TimeOfDay? endTime;

  const ShiftEntry({
    required this.type,
    this.startTime,
    this.endTime,
  });

  ShiftEntry copyWith({
    ShiftType? type,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
  }) {
    return ShiftEntry(
      type: type ?? this.type,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
    );
  }
}

class ShiftController extends ChangeNotifier {
  Team _currentTeam = Team.a;
  String _teamAName = 'A';
  String _teamBName = 'B';
  final List<ShiftType> _pattern = [ShiftType.day, ShiftType.night, ShiftType.off];
  final DateTime _startDate = DateTime(2026, 1, 1);
  final Map<String, ShiftEntry> _manualEntries = <String, ShiftEntry>{};

  Team get currentTeam => _currentTeam;
  String get teamAName => _teamAName;
  String get teamBName => _teamBName;
  String get currentTeamLabel => _currentTeam == Team.a ? _teamAName : _teamBName;

  String _dateKey(DateTime d) => DateTime(d.year, d.month, d.day).toIso8601String().split('T').first;

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final savedTeam = prefs.getString('selected_team');
    _currentTeam = _parseTeam(savedTeam) ?? _currentTeam;
    _teamAName = prefs.getString('team_a_name') ?? 'A';
    _teamBName = prefs.getString('team_b_name') ?? 'B';

    final savedManual = prefs.getString('manual_shifts');
    if (savedManual != null) {
      try {
        final raw = jsonDecode(savedManual);
        if (raw is Map) {
          _manualEntries.clear();
          raw.forEach((k, v) {
            if (k is! String) return;
            if (v is String) {
              final type = ShiftType.values.where((t) => t.name == v).firstOrNull;
              if (type != null) {
                _manualEntries[k] = ShiftEntry(type: type);
              }
            } else if (v is Map<String, dynamic>) {
              final type = ShiftType.values.where((t) => t.name == (v['type'] ?? 'off')).firstOrNull;
              if (type == null) return;
              _manualEntries[k] = ShiftEntry(
                type: type,
                startTime: _parseTime(v['start'] as String?),
                endTime: _parseTime(v['end'] as String?),
              );
            }
          });
        }
      } catch (e, st) {
        debugPrint('Failed to load manual shifts: $e');
        debugPrint(st.toString());
      }
    }
    notifyListeners();
  }

  Team? _parseTeam(String? value) {
    if (value == null) return null;
    try {
      return Team.values.byName(value);
    } catch (_) {
      return null;
    }
  }

  Future<void> toggleTeam() async {
    _currentTeam = _currentTeam == Team.a ? Team.b : Team.a;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_team', _currentTeam.name);
    notifyListeners();
  }

  Future<void> setTeamNames(String a, String b) async {
    _teamAName = a.trim().isEmpty ? 'A' : a.trim();
    _teamBName = b.trim().isEmpty ? 'B' : b.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('team_a_name', _teamAName);
    await prefs.setString('team_b_name', _teamBName);
    notifyListeners();
  }

  TimeOfDay? _parseTime(String? raw) {
    if (raw == null) return null;
    try {
      final parts = raw.split(':');
      if (parts.length != 2) return null;
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
      return TimeOfDay(hour: hour, minute: minute);
    } catch (_) {
      return null;
    }
  }

  String? _formatTime(TimeOfDay? t) {
    if (t == null) return null;
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _saveManual() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = <String, dynamic>{};
    _manualEntries.forEach((k, v) {
      encoded[k] = {
        'type': v.type.name,
        'start': _formatTime(v.startTime),
        'end': _formatTime(v.endTime),
      };
    });
    await prefs.setString('manual_shifts', jsonEncode(encoded));
  }

  ShiftEntry defaultEntryForType(ShiftType t) {
    switch (t) {
      case ShiftType.day:
        return const ShiftEntry(type: ShiftType.day, startTime: TimeOfDay(hour: 6, minute: 0), endTime: TimeOfDay(hour: 14, minute: 0));
      case ShiftType.evening:
        return const ShiftEntry(type: ShiftType.evening, startTime: TimeOfDay(hour: 14, minute: 0), endTime: TimeOfDay(hour: 22, minute: 0));
      case ShiftType.night:
        return const ShiftEntry(type: ShiftType.night, startTime: TimeOfDay(hour: 22, minute: 0), endTime: TimeOfDay(hour: 6, minute: 0));
      case ShiftType.off:
        return const ShiftEntry(type: ShiftType.off);
    }
  }

  ShiftEntry getEntryForDate(DateTime date) {
    final manual = _manualEntries[_dateKey(date)];
    if (manual != null) return manual;

    final daysDiff = date.difference(_startDate).inDays;
    int index = daysDiff % _pattern.length;
    if (_currentTeam == Team.b) index = (index + 1) % _pattern.length;
    return defaultEntryForType(_pattern[index]);
  }

  ShiftEntry? getManualEntry(DateTime date) => _manualEntries[_dateKey(date)];

  Future<void> setManualEntry(DateTime date, ShiftEntry entry) async {
    _manualEntries[_dateKey(date)] = entry;
    await _saveManual();
    notifyListeners();
  }

  Future<void> clearManualEntry(DateTime date) async {
    _manualEntries.remove(_dateKey(date));
    await _saveManual();
    notifyListeners();
  }
}

class ShiftMasterApp extends StatelessWidget {
  const ShiftMasterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: const DashboardScreen(),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final ShiftController _controller;
  late DateTime _displayMonth;
  static const List<String> _imageExtensions = <String>['.png', '.jpg', '.jpeg', '.webp', '.bmp'];
  static const double _dayFontSize = 20;
  static const double _dayCellAspectRatio = 1.22;
  static const double _holidayDotOffsetY = 3;
  static const double _holidayNameOffsetY = 5;
  static const List<String> _holidayFontFallback = [
    'Malgun Gothic',
    'Apple SD Gothic Neo',
    'Noto Sans KR',
    'sans-serif',
  ];

  @override
  void initState() {
    super.initState();
    _controller = ShiftController()..loadSettings();
    final now = DateTime.now();
    _displayMonth = DateTime(now.year, now.month, 1);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<DateTime?> _monthCells(DateTime now) {
    final first = DateTime(now.year, now.month, 1);
    final days = DateUtils.getDaysInMonth(now.year, now.month);
    final leading = first.weekday % 7;
    final cells = List<DateTime?>.filled(leading, null, growable: true);
    for (int d = 1; d <= days; d++) {
      cells.add(DateTime(now.year, now.month, d));
    }
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    return cells;
  }

  String _symbol(ShiftType t) {
    switch (t) {
      case ShiftType.off:
        return '\ud734';
      case ShiftType.day:
        return '\uc8fc';
      case ShiftType.night:
        return '\uc57c';
      case ShiftType.evening:
        return '\uc624\ud6c4';
    }
  }

  Color _fillColor(ShiftType t) {
    switch (t) {
      case ShiftType.off:
        return const Color(0xFFDCA9B6);
      case ShiftType.day:
        return const Color(0xFFA8CED3);
      case ShiftType.night:
        return const Color(0xFFD2CFA2);
      case ShiftType.evening:
        return const Color(0xFFC5B1D7);
    }
  }

  String? _koreanHoliday(DateTime d) {
    final key = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    const kr2026 = <String, String>{
      '2026-01-01': '\uc2e0\uc815',
      '2026-02-16': '\uc124\uc5f0\ud734',
      '2026-02-17': '\uc124\ub0a0',
      '2026-02-18': '\uc124\uc5f0\ud734',
      '2026-03-01': '\uc0bc\uc77c\uc808',
      '2026-03-02': '\ub300\uccb4',
      '2026-05-05': '\uc5b4\ub9b0\uc774\ub0a0',
      '2026-05-24': '\ubd80\ucc98\ub2d8\uc624\uc2e0\ub0a0',
      '2026-06-06': '\ud604\ucda9\uc77c',
      '2026-08-15': '\uad11\ubcf5\uc808',
      '2026-09-24': '\ucd94\uc11d\uc5f0\ud734',
      '2026-09-25': '\ucd94\uc11d',
      '2026-09-26': '\ucd94\uc11d\uc5f0\ud734',
      '2026-10-03': '\uac1c\ucc9c\uc808',
      '2026-10-05': '\ub300\uccb4',
      '2026-10-09': '\ud55c\uae00\ub0a0',
      '2026-12-25': '\uc131\ud0c4\uc808',
    };
    return kr2026[key];
  }

  Widget _buildMonthCell(BuildContext context, DateTime? d, DateTime today, {required bool enableInteraction}) {
    if (d == null) {
      return Container(decoration: BoxDecoration(border: Border.all(color: _ShiftMasterTheme.dayCellBorder)));
    }

    final isToday = DateTime(d.year, d.month, d.day) == today;
    final entry = _controller.getEntryForDate(d);
    final holiday = _koreanHoliday(d);
    final holidayDot = Container(
      width: 20,
      height: 20,
      decoration: const BoxDecoration(
        color: Color(0xFFE55063),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: const Text(
        '\uacf5',
        style: TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          height: 1,
          fontFamilyFallback: _holidayFontFallback,
        ),
        textAlign: TextAlign.center,
      ),
    );
    final holidayNameText = Text(
      holiday ?? '',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Color(0xFFD93E53),
        fontSize: 16,
        fontWeight: FontWeight.w800,
        height: 1,
        fontFamilyFallback: _holidayFontFallback,
      ),
    );

    return InkWell(
      onTap: enableInteraction ? () => _showAddShiftSheet(context, initialDate: d) : null,
      child: Container(
      decoration: BoxDecoration(
          border: Border.all(color: _ShiftMasterTheme.dayCellBorder),
          color: Colors.white,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 1, 2, 1),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${d.day}',
                    style: TextStyle(
                      fontSize: _dayFontSize,
                      color: isToday ? Colors.black : const Color(0xFF888888),
                      fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                  if (holiday != null) const SizedBox(width: 3),
                  if (holiday != null)
                    Transform.translate(
                      offset: const Offset(0, _holidayDotOffsetY),
                      child: holidayDot,
                    ),
                  if (holiday != null) const SizedBox(width: 3),
                  if (holiday != null)
                    Expanded(
                      child: Transform.translate(
                        offset: const Offset(0, _holidayNameOffsetY),
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: holidayNameText,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(1, 0, 1, 1),
                color: _fillColor(entry.type),
                child: Center(
                  child: Text(
                    _symbol(entry.type),
                    style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800, height: 1),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthGrid(List<DateTime?> cells, DateTime today, {required bool enableInteraction, required bool faded}) {
    final grid = GridView.builder(
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: cells.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisSpacing: 0,
        crossAxisSpacing: 0,
        childAspectRatio: _dayCellAspectRatio,
      ),
      itemBuilder: (context, i) => _buildMonthCell(context, cells[i], today, enableInteraction: enableInteraction),
    );

    if (!faded) return grid;

    return Opacity(
      opacity: 0.45,
      child: IgnorePointer(
        ignoring: !enableInteraction,
        child: grid,
      ),
    );
  }

  DateTime _monthFromOffset(int offset) {
    final baseIndex = _displayMonth.year * 12 + (_displayMonth.month - 1) + offset;
    final year = baseIndex ~/ 12;
    final month = (baseIndex % 12) + 1;
    return DateTime(year, month, 1);
  }

  void _shiftMonth(int offset) {
    setState(() {
      _displayMonth = _monthFromOffset(offset);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final displayMonth = DateTime(_displayMonth.year, _displayMonth.month, 1);
        final cells = _monthCells(displayMonth);
        final nextMonthCells = _monthCells(_monthFromOffset(1)).take(14).toList();
        const week = ['\uc77c', '\uc6d4', '\ud654', '\uc218', '\ubaa9', '\uae08', '\ud1a0'];
        final nextMonthPreviewHeight = (MediaQuery.of(context).size.width / 7) / _dayCellAspectRatio * 2;

        return Scaffold(
          backgroundColor: _ShiftMasterTheme.appBackground,
          body: SafeArea(
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  decoration: const BoxDecoration(
                    color: _ShiftMasterTheme.headerBackground,
                    borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                onPressed: () => _shiftMonth(-1),
                                icon: const Icon(Icons.chevron_left, color: Colors.white),
                                tooltip: '이전 월',
                              ),
                              Text(
                                '${displayMonth.year}\ub144 ${displayMonth.month.toString().padLeft(2, '0')}\uc6d4',
                                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
                              ),
                              IconButton(
                                onPressed: () => _shiftMonth(1),
                                icon: const Icon(Icons.chevron_right, color: Colors.white),
                                tooltip: '다음 월',
                              ),
                            ],
                          ),
                        ),
                      ),
                      GestureDetector(
                        onLongPress: () => _showTeamNameDialog(context),
                        child: Row(
                          children: [
                            TextButton(
                              onPressed: _controller.toggleTeam,
                              child: Text(
                                '\ud300 ${_controller.currentTeamLabel}',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                              ),
                            ),
                            IconButton(
                              onPressed: () => _showTeamNameDialog(context),
                              icon: const Icon(Icons.edit, color: Colors.white, size: 18),
                              tooltip: '\ud300 \uc774\ub984 \ubcc0\uacbd',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Row(
                    children: week
                        .map((w) => Expanded(child: Text(w, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700))))
                        .toList(),
                  ),
                ),
                Expanded(
                  child: _buildMonthGrid(
                    cells,
                    today,
                    enableInteraction: true,
                    faded: false,
                  ),
                ),
                Container(
                  margin: const EdgeInsets.fromLTRB(8, 6, 8, 4),
                  height: nextMonthPreviewHeight,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: _ShiftMasterTheme.dayCellBorder, width: 0.5),
                  ),
                  child: _buildMonthGrid(
                    nextMonthCells,
                    today,
                    enableInteraction: false,
                    faded: true,
                  ),
                ),
                Container(
                  color: _ShiftMasterTheme.toolbarBackground,
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
                  child: FilledButton(
                    onPressed: () => _showAddShiftSheet(context),
                    child: const Text('\uadfc\ubb34 \uc785\ub825'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatTime(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<TimeOfDay?> _pickTime(BuildContext context, TimeOfDay initial) async {
    return showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );
  }

  String _shiftTypeLabel(ShiftType t) {
    switch (t) {
      case ShiftType.day:
        return '\uc8fc\uac04';
      case ShiftType.evening:
        return '\uc624\ud6c4';
      case ShiftType.night:
        return '\uc57c\uac04';
      case ShiftType.off:
        return '\ud734\ubb34';
    }
  }

  void _showSnackBar(BuildContext context, String message, {bool isError = false}) {
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? _ShiftMasterTheme.errorBannerBackground : null,
        contentTextStyle: isError
            ? const TextStyle(color: _ShiftMasterTheme.errorBannerForeground, fontWeight: FontWeight.w700)
            : null,
      ),
    );
  }

  bool _isShiftTimeValid(ShiftType type, TimeOfDay? start, TimeOfDay? end) {
    if (type == ShiftType.off) return true;
    if (start == null || end == null) return false;
    if (type == ShiftType.night) return true;
    final startMinutes = start.hour * 60 + start.minute;
    final endMinutes = end.hour * 60 + end.minute;
    return endMinutes > startMinutes;
  }

  ShiftEntry _normalizeShiftForSave(ShiftEntry entry) {
    if (entry.type == ShiftType.off) return const ShiftEntry(type: ShiftType.off);
    final base = _controller.defaultEntryForType(entry.type);
    return entry.copyWith(
      startTime: entry.startTime ?? base.startTime,
      endTime: entry.endTime ?? base.endTime,
    );
  }

  bool _canOpenDesktopImage() {
    return !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.linux);
  }

  Future<void> _showTeamNameDialog(BuildContext context) async {
    final aController = TextEditingController(text: _controller.teamAName);
    final bController = TextEditingController(text: _controller.teamBName);
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('\ud300 \uc774\ub984 \uc124\uc815'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: aController,
                decoration: const InputDecoration(labelText: '\ud300 A \uc774\ub984'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: bController,
                decoration: const InputDecoration(labelText: '\ud300 B \uc774\ub984'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('\ucde8\uc18c'),
            ),
            FilledButton(
              onPressed: () async {
                final teamA = aController.text.trim();
                final teamB = bController.text.trim();
                if (teamA.isEmpty || teamB.isEmpty) {
                  _showSnackBar(context, '팀 이름은 비어 있을 수 없습니다.', isError: true);
                  return;
                }
                if (teamA == teamB) {
                  _showSnackBar(context, '두 팀 이름이 동일합니다. 다르게 입력하세요.', isError: true);
                  return;
                }
                await _controller.setTeamNames(teamA, teamB);
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('\uc800\uc7a5'),
            ),
          ],
        );
      },
    );
  }

  String? _findDesktopImagePath(String baseName) {
    if (!_canOpenDesktopImage()) return null;
    try {
      return findDesktopImagePath(baseName, _imageExtensions);
    } catch (_) {
      return null;
    }
  }

  Future<void> _openDesktopImage(BuildContext context, String baseName) async {
    if (!_canOpenDesktopImage()) {
      _showSnackBar(context, '바탕화면 이미지 열기는 웹/모바일에서는 지원되지 않습니다.', isError: true);
      return;
    }

    final path = _findDesktopImagePath(baseName);
    if (path == null) {
      _showSnackBar(context, '바탕화면에 $baseName.(png/jpg/jpeg/webp/bmp) 파일이 없습니다.', isError: true);
      return;
    }

    final opened = await launchUrl(
      Uri.file(path),
      mode: LaunchMode.externalApplication,
    );

    if (!context.mounted) return;
    if (!opened) {
      _showSnackBar(context, '$baseName 파일을 열지 못했습니다.', isError: true);
    }
  }

  void _showAddShiftSheet(BuildContext context, {DateTime? initialDate}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        DateTime selectedDate = initialDate ?? DateTime.now();
        ShiftEntry selected = _controller.getEntryForDate(selectedDate);

        return Container(
          padding: EdgeInsets.fromLTRB(18, 14, 18, 14 + MediaQuery.of(context).viewInsets.bottom),
          decoration: const BoxDecoration(
            color: _ShiftMasterTheme.sheetBackground,
            borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
          ),
          child: StatefulBuilder(
            builder: (context, setModal) {
              final hasManual = _controller.getManualEntry(selectedDate) != null;
              final showTime = selected.type != ShiftType.off;
              final start = selected.startTime ?? const TimeOfDay(hour: 9, minute: 0);
              final end = selected.endTime ?? const TimeOfDay(hour: 18, minute: 0);

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('\uadfc\ubb34 \uc785\ub825', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  const Text('\uc800\uc7a5\ud558\uba74 \ub2e4\uc74c \ub0a0\uc9dc\ub85c \uc790\ub3d9 \uc774\ub3d9\ud569\ub2c8\ub2e4.', style: TextStyle(fontSize: 12)),
                  const SizedBox(height: 8),
                  const Text('\uadfc\ubb34 \uc124\uc815 \ucc38\uace0\uc0ac\uc9c4', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _openDesktopImage(context, '1'),
                        icon: const Icon(Icons.photo),
                        label: const Text('1 \uc0ac\uc9c4 \uc5f4\uae30'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _openDesktopImage(context, '2'),
                        icon: const Icon(Icons.photo),
                        label: const Text('2 \uc0ac\uc9c4 \uc5f4\uae30'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2024, 1, 1),
                        lastDate: DateTime(2030, 12, 31),
                      );
                      if (picked != null) {
                        setModal(() {
                          selectedDate = picked;
                          selected = _controller.getEntryForDate(selectedDate);
                        });
                      }
                    },
                    icon: const Icon(Icons.calendar_month),
                    label: Text('${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}'),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<ShiftType>(
                    initialValue: selected.type,
                    decoration: const InputDecoration(labelText: '\uadfc\ubb34 \uc885\ub958', border: OutlineInputBorder()),
                    items: ShiftType.values.map((t) => DropdownMenuItem<ShiftType>(value: t, child: Text(_shiftTypeLabel(t)))).toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setModal(() {
                        final base = _controller.defaultEntryForType(v);
                        selected = selected.copyWith(type: v, startTime: base.startTime, endTime: base.endTime);
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  if (showTime)
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              final picked = await _pickTime(context, start);
                              if (picked != null) setModal(() => selected = selected.copyWith(startTime: picked));
                            },
                            child: Text('\uc2dc\uc791 ${_formatTime(start)}'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              final picked = await _pickTime(context, end);
                              if (picked != null) setModal(() => selected = selected.copyWith(endTime: picked));
                            },
                            child: Text('\uc885\ub8cc ${_formatTime(end)}'),
                          ),
                        ),
                      ],
                    ),
                  if (showTime) const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: () async {
                            final normalized = _normalizeShiftForSave(selected);
                            if (!_isShiftTimeValid(normalized.type, normalized.startTime, normalized.endTime)) {
                              _showSnackBar(context, '종료 시간이 시작 시간보다 빠릅니다.', isError: true);
                              return;
                            }
                            await _controller.setManualEntry(selectedDate, normalized);
                            if (!context.mounted) return;
                            setModal(() {
                              selectedDate = selectedDate.add(const Duration(days: 1));
                              selected = _controller.getEntryForDate(selectedDate);
                            });
                            _showSnackBar(context, '저장되었습니다.');
                          },
                          child: const Text('\uc800\uc7a5 + \ub2e4\uc74c'),
                        ),
                      ),
                      if (hasManual) const SizedBox(width: 8),
                      if (hasManual)
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              await _controller.clearManualEntry(selectedDate);
                              if (!context.mounted) return;
                              setModal(() {
                                selected = _controller.getEntryForDate(selectedDate);
                              });
                            },
                            child: const Text('\uc218\ub3d9 \ud574\uc81c'),
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}




