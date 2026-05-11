import 'dart:async';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/index_service.dart';
import '../services/settings_service.dart';
import '../widgets/result_card.dart';
import '../widgets/syntax_help_sheet.dart';

/// Main screen — mirrors the C# MainWindow / MainViewModel.
class MainScreen extends StatefulWidget {
  final SettingsService settings;

  const MainScreen({super.key, required this.settings});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  // ── Services ──────────────────────────────────────────────────
  final _indexService = IndexService();

  // ── Controllers ───────────────────────────────────────────────
  final _searchController = TextEditingController();
  final _distanceController = TextEditingController(text: '10');
  final _scrollController = ScrollController();

  // ── State ─────────────────────────────────────────────────────
  bool _isIndexing = false;
  bool _isSearching = false;
  double _indexProgress = 0; // 0..100
  int _indexedLines = 0;
  int _totalLines = 0;
  String _statusText = 'מוכן';
  String _resultCountText = '';
  bool _requireOrdered = false;
  String _currentQuery = '';

  final List<SearchResultItem> _results = [];

  // Cancellation flags
  bool _cancelIndex = false;
  bool _cancelSearch = false;

  // Elapsed / ETA
  Stopwatch? _stopwatch;
  Timer? _elapsedTimer;
  String _elapsedText = '';
  String _etaText = '';

  // ── Lifecycle ─────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _tryOpenExistingIndex();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _distanceController.dispose();
    _scrollController.dispose();
    _elapsedTimer?.cancel();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────

  int get _maxWordDistance =>
      int.tryParse(_distanceController.text.trim()) ?? 10;

  bool get _canSearch =>
      !_isSearching &&
      (_indexService.isReady || _isIndexing) &&
      _searchController.text.trim().isNotEmpty;

  void _tryOpenExistingIndex() {
    final dbPath = widget.settings.indexedDbPath;
    if (dbPath.isEmpty) return;
    if (!_indexService.indexExists(dbPath)) return;
    try {
      _indexService.open(dbPath);
      setState(() => _statusText = 'אינדקס טעון: ${_fileName(dbPath)}');
    } catch (e) {
      setState(() => _statusText = 'לא ניתן לפתוח אינדקס: $e');
    }
  }

  String _fileName(String path) =>
      path.split(RegExp(r'[/\\]')).last;

  // ── Build index ───────────────────────────────────────────────

  Future<void> _onBuildIndex() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['db'],
      dialogTitle: 'בחר קובץ מסד נתונים',
    );
    if (result == null || result.files.single.path == null) return;

    final dbPath = result.files.single.path!;

    if (_indexService.indexExists(dbPath)) {
      final confirmed = await _showConfirmDialog(
        'אינדקס קיים כבר עבור קובץ זה. האם לבנות מחדש?',
        'בניית אינדקס',
      );
      if (!confirmed) return;
    }

    _indexService.close();
    setState(() {
      _results.clear();
      _resultCountText = '';
      _isIndexing = true;
      _indexProgress = 0;
      _indexedLines = 0;
      _totalLines = 0;
      _statusText = 'בונה אינדקס…';
      _elapsedText = '';
      _etaText = '';
      _cancelIndex = false;
    });

    _stopwatch = Stopwatch()..start();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _elapsedText = _formatDuration(_stopwatch!.elapsed);
        _updateEta();
      });
    });

    bool success = false;
    try {
      await _indexService.build(
        dbPath,
        onProgress: (indexed, total) {
          if (!mounted) return;
          setState(() {
            _indexedLines = indexed;
            _totalLines = total;
            _indexProgress = total > 0 ? 100.0 * indexed / total : 0;
          });
        },
        isCancelled: () => _cancelIndex,
      );
      success = true;
    } catch (e) {
      if (mounted) {
        setState(() => _statusText = 'שגיאה בבניית האינדקס: $e');
        _showErrorDialog('שגיאה בבניית האינדקס', e.toString());
      }
    } finally {
      _elapsedTimer?.cancel();
      _elapsedTimer = null;
      _stopwatch?.stop();
      if (mounted) {
        setState(() {
          _isIndexing = false;
          _indexProgress = success ? 100 : 0;
          _elapsedText = '';
          _etaText = '';
        });
      }
    }

    if (success && mounted) {
      await widget.settings.setIndexedDbPath(dbPath);
      _tryOpenExistingIndex();
      setState(() => _statusText = 'האינדקס נבנה בהצלחה');

      // Auto-re-search if the user had a query running during the build.
      if (_currentQuery.isNotEmpty && _results.isNotEmpty) {
        _searchController.text = _currentQuery;
        await _onSearch();
      }
    }
  }

  void _onCancelIndex() {
    setState(() => _cancelIndex = true);
    setState(() => _statusText = 'מבטל…');
  }

  // ── Search ────────────────────────────────────────────────────

  Future<void> _onSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    // Cancel any previous search
    setState(() => _cancelSearch = true);
    await Future.delayed(const Duration(milliseconds: 30));

    setState(() {
      _cancelSearch = false;
      _isSearching = true;
      _results.clear();
      _resultCountText = '';
      _currentQuery = query;
      _statusText = _isIndexing ? 'מחפש (בזמן בניית אינדקס)…' : 'מחפש…';
    });

    try {
      await for (final item in _indexService.search(
        query,
        maxWordDistance: _maxWordDistance,
        requireOrdered: _requireOrdered,
        isCancelled: () => _cancelSearch,
      )) {
        if (!mounted || _cancelSearch) break;
        setState(() {
          _results.add(item);
          _resultCountText =
              'נמצאו ${NumberFormat('#,###').format(_results.length)} תוצאות';
        });
      }

      if (mounted && !_cancelSearch) {
        setState(() {
          _statusText = _results.isEmpty
              ? 'לא נמצאו תוצאות'
              : 'נמצאו ${NumberFormat('#,###').format(_results.length)} תוצאות';
          if (_results.isEmpty) _resultCountText = _statusText;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusText = 'שגיאה בחיפוש: $e';
          _resultCountText = _statusText;
        });
      }
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  // ── ETA ───────────────────────────────────────────────────────

  void _updateEta() {
    const baselineMinutes = 25.0;
    final pct = _indexProgress;
    final elapsed = _stopwatch?.elapsed ?? Duration.zero;

    if (pct <= 0) {
      _etaText = '~${baselineMinutes.toStringAsFixed(0)} דק׳';
      return;
    }

    Duration remaining;
    if (pct >= 1.0) {
      final totalSec = elapsed.inSeconds / (pct / 100.0);
      final remainSec = (totalSec - elapsed.inSeconds).clamp(0, double.infinity);
      remaining = Duration(seconds: remainSec.toInt());
    } else {
      final baselineSec = baselineMinutes * 60;
      remaining = Duration(
          seconds: (baselineSec - elapsed.inSeconds).clamp(0, baselineSec).toInt());
    }

    _etaText = remaining.inHours >= 1
        ? '~${_formatDuration(remaining)}'
        : '~${remaining.inMinutes.toString().padLeft(2, '0')}:${(remaining.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  String _formatDuration(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  // ── Dialogs ───────────────────────────────────────────────────

  Future<bool> _showConfirmDialog(String message, String title) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('לא')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('כן')),
          ],
        ),
      ),
    );
    return result ?? false;
  }

  Future<void> _showErrorDialog(String title, String message) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('סגור')),
          ],
        ),
      ),
    );
  }

  void _showSyntaxHelp() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const SyntaxHelpSheet(),
    );
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Column(
          children: [
            _buildToolbar(),
            if (_isSearching) _buildSearchProgressBar(),
            if (_isIndexing) _buildIndexProgressBar(),
            Expanded(child: _buildResultsList()),
            _buildStatusBar(),
          ],
        ),
      ),
    );
  }

  // ── Toolbar ───────────────────────────────────────────────────

  Widget _buildToolbar() {
    return Container(
      color: const Color(0xFFF5F5F5),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFDDDDDD))),
      ),
      child: Column(
        children: [
          // Search row
          Row(
            children: [
              // Info button
              _InfoButton(onTap: _showSyntaxHelp),
              const SizedBox(width: 8),

              // Search field
              Expanded(
                child: TextField(
                  controller: _searchController,
                  textDirection: ui.TextDirection.rtl,
                  decoration: InputDecoration(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: const BorderSide(color: Color(0xFFAAAAAA)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: const BorderSide(color: Color(0xFFAAAAAA)),
                    ),
                    isDense: true,
                  ),
                  onSubmitted: (_) {
                    if (_canSearch) _onSearch();
                  },
                ),
              ),
              const SizedBox(width: 8),

              // Search button
              _PrimaryButton(
                onPressed: _canSearch ? _onSearch : null,
                tooltip: 'חפש',
                child: const Icon(Icons.search, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 6),

              // Build / Cancel index button
              if (!_isIndexing)
                _PrimaryButton(
                  onPressed: _isSearching ? null : _onBuildIndex,
                  label: 'צור אינדקס',
                )
              else
                _DangerButton(
                  onPressed: _onCancelIndex,
                  label: 'בטל',
                ),
            ],
          ),

          const SizedBox(height: 6),

          // Word distance row
          Row(
            children: [
              const Text('מרחק מקסימלי בין מילים:',
                  style: TextStyle(fontSize: 12, color: Color(0xFF555555))),
              const Spacer(),
              SizedBox(
                width: 52,
                child: TextField(
                  controller: _distanceController,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: const BorderSide(color: Color(0xFFAAAAAA)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: const BorderSide(color: Color(0xFFAAAAAA)),
                    ),
                    isDense: true,
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),

          const SizedBox(height: 6),

          // Order mode row
          Row(
            children: [
              const Text('סדר מילים:',
                  style: TextStyle(fontSize: 12, color: Color(0xFF555555))),
              const SizedBox(width: 10),
              _RadioOption(
                label: 'לא מסודר',
                value: false,
                groupValue: _requireOrdered,
                onChanged: (v) => setState(() => _requireOrdered = v!),
              ),
              const SizedBox(width: 14),
              _RadioOption(
                label: 'לפי סדר השאילתה',
                value: true,
                groupValue: _requireOrdered,
                onChanged: (v) => setState(() => _requireOrdered = v!),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Progress bars ─────────────────────────────────────────────

  Widget _buildSearchProgressBar() {
    return LinearProgressIndicator(
      minHeight: 3,
      backgroundColor: Colors.transparent,
      color: const Color(0xFF2E6DA4),
    );
  }

  Widget _buildIndexProgressBar() {
    final pct = _indexProgress;
    final detail = _totalLines > 0
        ? '${NumberFormat('#,###').format(_indexedLines)} / '
            '${NumberFormat('#,###').format(_totalLines)}  '
            '(${pct.toStringAsFixed(1)}%)'
        : '${NumberFormat('#,###').format(_indexedLines)} שורות';

    return Container(
      color: const Color(0xFFFFFBF0),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF0C040))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$detail   $_elapsedText',
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF7A5800)),
                ),
              ),
              if (_etaText.isNotEmpty)
                Text(
                  'נותר: $_etaText',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF7A5800)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct / 100.0,
              minHeight: 8,
              backgroundColor: const Color(0xFFE0E0E0),
              color: const Color(0xFF2E6DA4),
            ),
          ),
        ],
      ),
    );
  }

  // ── Results list ──────────────────────────────────────────────

  Widget _buildResultsList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_resultCountText.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Text(
              _resultCountText,
              style: const TextStyle(fontSize: 13, color: Color(0xFF70757A)),
            ),
          ),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            itemCount: _results.length,
            itemBuilder: (ctx, i) => ResultCard(item: _results[i]),
          ),
        ),
      ],
    );
  }

  // ── Status bar ────────────────────────────────────────────────

  Widget _buildStatusBar() {
    final dbPath = widget.settings.indexedDbPath;
    return Container(
      color: const Color(0xFFEEEEEE),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFDDDDDD))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _statusText,
              style: const TextStyle(fontSize: 12, color: Color(0xFF444444)),
            ),
          ),
          if (dbPath.isNotEmpty)
            Text(
              'DB: ${_fileName(dbPath)}',
              style: const TextStyle(fontSize: 11, color: Color(0xFF888888)),
            ),
        ],
      ),
    );
  }
}

// ── Small reusable widgets ────────────────────────────────────────

class _PrimaryButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String? label;
  final Widget? child;
  final String? tooltip;

  const _PrimaryButton({
    this.onPressed,
    this.label,
    this.child,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final btn = ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF2E6DA4),
        foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0xFFAAAAAA),
        padding: label != null
            ? const EdgeInsets.symmetric(horizontal: 14, vertical: 6)
            : const EdgeInsets.all(8),
        minimumSize: label != null ? const Size(90, 34) : const Size(36, 34),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        elevation: 0,
      ),
      child: child ?? Text(label ?? ''),
    );
    if (tooltip != null) return Tooltip(message: tooltip!, child: btn);
    return btn;
  }
}

class _DangerButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String label;

  const _DangerButton({required this.onPressed, required this.label});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFFC0392B),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        minimumSize: const Size(90, 34),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        elevation: 0,
      ),
      child: Text(label),
    );
  }
}

class _InfoButton extends StatelessWidget {
  final VoidCallback onTap;
  const _InfoButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'תחביר חיפוש',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF2E6DA4), width: 1.5),
          ),
          child: const Center(
            child: Text(
              'i',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2E6DA4)),
            ),
          ),
        ),
      ),
    );
  }
}

class _RadioOption extends StatelessWidget {
  final String label;
  final bool value;
  final bool groupValue;
  final ValueChanged<bool?> onChanged;

  const _RadioOption({
    required this.label,
    required this.value,
    required this.groupValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Radio<bool>(
          value: value,
          groupValue: groupValue,
          onChanged: onChanged,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
