import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/notebook.dart';
import '../services/notebook_store.dart';
import 'canvas_screen.dart';

class NotebookLibraryScreen extends StatefulWidget {
  const NotebookLibraryScreen({super.key});

  @override
  State<NotebookLibraryScreen> createState() => _NotebookLibraryScreenState();
}

class _NotebookLibraryScreenState extends State<NotebookLibraryScreen> {
  static const _ink = Color(0xFF302F2A);
  static const _muted = Color(0xFF88857D);
  static const _paper = Color(0xFFFAF8F2);
  static const _sidebar = Color(0xFFF2EFE7);
  static const _accent = Color(0xFF647866);
  static const _coverColors = [
    Color(0xFFDCE5D8),
    Color(0xFFE9DDC7),
    Color(0xFFEBD8D3),
    Color(0xFFDCE3E8),
    Color(0xFFE8E5D8),
  ];

  final _searchController = TextEditingController();
  final List<Notebook> _notebooks = [];
  String _filter = 'all';
  String _query = '';
  String _sort = 'recent';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadNotebooks();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadNotebooks() async {
    final loaded = await NotebookStore.load();
    if (!mounted) return;
    setState(() {
      _notebooks
        ..clear()
        ..addAll(loaded);
      _loading = false;
    });
  }

  Future<void> _save() => NotebookStore.save(_notebooks);

  List<Notebook> get _visibleNotebooks {
    var result = _notebooks.where((notebook) {
      if (_filter == 'favorites' && !notebook.isFavorite) return false;
      if (_filter != 'all' && _filter != 'favorites' && _filter != 'recent' &&
          notebook.id != _filter) {
        return false;
      }
      return _query.isEmpty || notebook.title.toLowerCase().contains(_query);
    }).toList();
    result.sort((a, b) => _sort == 'name'
        ? a.title.toLowerCase().compareTo(b.title.toLowerCase())
        : b.updatedAt.compareTo(a.updatedAt));
    if (_filter == 'recent') result = result.take(8).toList();
    return result;
  }

  String get _pageTitle {
    if (_filter == 'favorites') return 'Starred notebooks';
    if (_filter == 'recent') return 'Recently edited';
    if (_filter == 'all') return 'All notebooks';
    final matches = _notebooks.where((notebook) => notebook.id == _filter);
    return matches.isEmpty ? 'Notebook' : matches.first.title;
  }

  Future<void> _createNotebook() async {
    final name = await _showNameDialog(title: 'New notebook', hint: 'e.g. Lecture notes');
    if (name == null || name.isEmpty) return;
    final now = DateTime.now();
    setState(() {
      _notebooks.insert(
        0,
        Notebook(
          id: now.microsecondsSinceEpoch.toString(),
          title: name,
          colorValue: _coverColors[_notebooks.length % _coverColors.length].toARGB32(),
          createdAt: now,
          updatedAt: now,
        ),
      );
      _filter = 'all';
    });
    await _save();
  }

  Future<String?> _showNameDialog({required String title, String? initial, String? hint}) async {
    final controller = TextEditingController(text: initial ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _paper,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text(title, style: GoogleFonts.lora(color: _ink, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 48,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: hint ?? 'Notebook name',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          ),
          onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _accent, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result?.trim();
  }

  Future<void> _renameNotebook(Notebook notebook) async {
    final name = await _showNameDialog(title: 'Rename notebook', initial: notebook.title);
    if (name == null || name.isEmpty) return;
    setState(() {
      final index = _notebooks.indexWhere((item) => item.id == notebook.id);
      if (index >= 0) _notebooks[index] = notebook.copyWith(title: name, updatedAt: DateTime.now());
    });
    await _save();
  }

  Future<void> _toggleFavorite(Notebook notebook) async {
    setState(() {
      final index = _notebooks.indexWhere((item) => item.id == notebook.id);
      if (index >= 0) {
        _notebooks[index] = notebook.copyWith(isFavorite: !notebook.isFavorite);
      }
    });
    await _save();
  }

  Future<void> _duplicateNotebook(Notebook notebook) async {
    final now = DateTime.now();
    setState(() {
      _notebooks.insert(
        0,
        Notebook(
          id: now.microsecondsSinceEpoch.toString(),
          title: '${notebook.title} copy',
          colorValue: notebook.colorValue,
          createdAt: now,
          updatedAt: now,
        ),
      );
      _filter = 'all';
    });
    await _save();
  }

  Future<void> _deleteNotebook(Notebook notebook) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _paper,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text('Delete notebook?', style: GoogleFonts.lora(color: _ink, fontWeight: FontWeight.w700)),
        content: Text('“${notebook.title}” will be removed from this device.', style: const TextStyle(color: _muted, height: 1.45)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Keep it')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB75D50), foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _notebooks.removeWhere((item) => item.id == notebook.id);
      if (_filter == notebook.id) _filter = 'all';
    });
    await _save();
  }

  Future<void> _openNotebook(Notebook notebook) async {
    final index = _notebooks.indexWhere((item) => item.id == notebook.id);
    if (index >= 0) {
      setState(() => _notebooks[index] = notebook.copyWith(updatedAt: DateTime.now()));
      await _save();
    }
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CanvasScreen()));
  }

  void _selectFilter(String filter, {bool closeDrawer = false}) {
    setState(() => _filter = filter);
    if (closeDrawer) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isTablet = constraints.maxWidth >= 900;
        if (isTablet) {
          return Scaffold(
            backgroundColor: _paper,
            body: Row(
              children: [
                SizedBox(width: 264, child: _buildSidebar()),
                Expanded(child: SafeArea(child: _buildLibrary(compact: false))),
              ],
            ),
          );
        }
        return Scaffold(
          backgroundColor: _paper,
          drawer: Drawer(
            width: 292,
            backgroundColor: _sidebar,
            child: SafeArea(child: _buildSidebar(closeDrawer: true)),
          ),
          body: SafeArea(child: _buildLibrary(compact: true)),
        );
      },
    );
  }

  Widget _buildSidebar({bool closeDrawer = false}) {
    return Container(
      color: _sidebar,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 18, 22),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(color: _accent, borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.auto_stories_rounded, color: Colors.white, size: 21),
                  ),
                  const SizedBox(width: 11),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Folio', style: GoogleFonts.lora(fontSize: 19, fontWeight: FontWeight.w700, color: _ink)),
                      const Text('YOUR PAPER SPACE', style: TextStyle(fontSize: 9, letterSpacing: 1.35, color: _muted, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: FilledButton.icon(
                onPressed: _createNotebook,
                style: FilledButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('New notebook', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 28),
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 16, 8),
              child: Text('LIBRARY', style: TextStyle(fontSize: 10, letterSpacing: 1.35, fontWeight: FontWeight.w700, color: _muted)),
            ),
            _sidebarItem(icon: Icons.grid_view_rounded, label: 'All notebooks', filter: 'all', count: _notebooks.length, closeDrawer: closeDrawer),
            _sidebarItem(icon: Icons.star_rounded, label: 'Starred', filter: 'favorites', count: _notebooks.where((item) => item.isFavorite).length, closeDrawer: closeDrawer),
            _sidebarItem(icon: Icons.schedule_rounded, label: 'Recently edited', filter: 'recent', closeDrawer: closeDrawer),
            const SizedBox(height: 22),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 16, 8),
              child: Row(
                children: [
                  const Expanded(child: Text('NOTEBOOKS', style: TextStyle(fontSize: 10, letterSpacing: 1.35, fontWeight: FontWeight.w700, color: _muted))),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Create notebook',
                    onPressed: _createNotebook,
                    icon: const Icon(Icons.add_rounded, size: 18, color: _muted),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _notebooks.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.fromLTRB(24, 6, 20, 0),
                      child: Text('Your shelf is ready for its first notebook.', style: TextStyle(color: _muted, height: 1.4, fontSize: 12)),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 12),
                      itemCount: _notebooks.length,
                      itemBuilder: (context, index) {
                        final notebook = _notebooks[index];
                        return _sidebarItem(
                          icon: Icons.menu_book_rounded,
                          label: notebook.title,
                          filter: notebook.id,
                          dotColor: Color(notebook.colorValue),
                          closeDrawer: closeDrawer,
                        );
                      },
                    ),
            ),
            Container(
              margin: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: const Color(0xFFE7E4DA), borderRadius: BorderRadius.circular(14)),
              child: const Row(
                children: [
                  Icon(Icons.offline_pin_rounded, color: _accent, size: 18),
                  SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('On this device', style: TextStyle(fontSize: 12, color: _ink, fontWeight: FontWeight.w700)),
                        SizedBox(height: 2),
                        Text('Your library stays local', style: TextStyle(fontSize: 10, color: _muted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sidebarItem({
    required IconData icon,
    required String label,
    required String filter,
    int? count,
    Color? dotColor,
    bool closeDrawer = false,
  }) {
    final selected = _filter == filter;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: selected ? const Color(0xFFE3E7DF) : Colors.transparent,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: () => _selectFilter(filter, closeDrawer: closeDrawer),
          child: SizedBox(
            height: 42,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  if (dotColor != null)
                    Container(width: 9, height: 9, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle))
                  else
                    Icon(icon, size: 18, color: selected ? _accent : _muted),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: selected ? _ink : const Color(0xFF615F59), fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
                  ),
                  if (count != null && count > 0)
                    Text('$count', style: const TextStyle(fontSize: 11, color: _muted)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLibrary({required bool compact}) {
    final notebooks = _visibleNotebooks;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(compact ? 18 : 38, compact ? 12 : 28, compact ? 18 : 38, 12),
          child: Row(
            children: [
              if (compact)
                Builder(
                  builder: (context) => IconButton(
                    tooltip: 'Open navigation',
                    onPressed: () => Scaffold.of(context).openDrawer(),
                    icon: const Icon(Icons.menu_rounded, color: _ink),
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('YOUR LIBRARY', style: TextStyle(fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.w700, color: _accent.withAlpha(210))),
                    const SizedBox(height: 5),
                    Text(_pageTitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.lora(fontSize: compact ? 25 : 31, color: _ink, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              if (!compact) ...[
                _searchField(),
                const SizedBox(width: 12),
                _sortMenu(),
                const SizedBox(width: 12),
                _createButton(),
              ] else
                _createIconButton(),
            ],
          ),
        ),
        if (compact)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
            child: Row(children: [Expanded(child: _searchField(compact: true)), const SizedBox(width: 8), _sortMenu()]),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(38, 0, 38, 20),
            child: Row(
              children: [
                Text('${_notebooks.length} ${_notebooks.length == 1 ? 'notebook' : 'notebooks'}', style: const TextStyle(fontSize: 13, color: _muted)),
                const SizedBox(width: 7),
                const Icon(Icons.circle, size: 3, color: Color(0xFFB7B2A6)),
                const SizedBox(width: 7),
                const Text('Private to this tablet', style: TextStyle(fontSize: 13, color: _muted)),
              ],
            ),
          ),
        if (compact)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
            child: Align(alignment: Alignment.centerLeft, child: Text('${_notebooks.length} notebooks · private to this tablet', style: const TextStyle(fontSize: 12, color: _muted))),
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: _accent))
              : notebooks.isEmpty
                  ? _buildEmptyState()
                  : Padding(
                      padding: EdgeInsets.fromLTRB(compact ? 18 : 38, 0, compact ? 18 : 38, 20),
                      child: GridView.builder(
                        itemCount: notebooks.length,
                        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: compact ? 310 : 330,
                          mainAxisExtent: 264,
                          mainAxisSpacing: 18,
                          crossAxisSpacing: 18,
                        ),
                        itemBuilder: (context, index) => _notebookCard(notebooks[index]),
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _searchField({bool compact = false}) {
    return SizedBox(
      width: compact ? null : 254,
      height: 44,
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search notebooks',
          prefixIcon: const Icon(Icons.search_rounded, size: 19),
          filled: true,
          fillColor: const Color(0xFFF0EEE7),
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: BorderSide.none),
        ),
      ),
    );
  }

  Widget _sortMenu() => PopupMenuButton<String>(
    tooltip: 'Sort notebooks',
    initialValue: _sort,
    onSelected: (value) => setState(() => _sort = value),
    itemBuilder: (_) => const [
      PopupMenuItem(value: 'recent', child: Text('Recently edited')),
      PopupMenuItem(value: 'name', child: Text('Name A–Z')),
    ],
    child: Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: const Color(0xFFF0EEE7), borderRadius: BorderRadius.circular(13)),
      child: const Row(children: [Icon(Icons.sort_rounded, size: 18, color: _ink), SizedBox(width: 7), Text('Sort', style: TextStyle(fontSize: 12, color: _ink, fontWeight: FontWeight.w600))]),
    ),
  );

  Widget _createButton() => FilledButton.icon(
    onPressed: _createNotebook,
    style: FilledButton.styleFrom(backgroundColor: _accent, foregroundColor: Colors.white, minimumSize: const Size(156, 44), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13))),
    icon: const Icon(Icons.add_rounded, size: 19),
    label: const Text('New notebook'),
  );

  Widget _createIconButton() => IconButton.filled(
    tooltip: 'New notebook',
    onPressed: _createNotebook,
    style: IconButton.styleFrom(backgroundColor: _accent, foregroundColor: Colors.white),
    icon: const Icon(Icons.add_rounded),
  );

  Widget _buildEmptyState() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 112,
              height: 112,
              decoration: const BoxDecoration(color: Color(0xFFEAE7DE), shape: BoxShape.circle),
              child: const Icon(Icons.menu_book_rounded, size: 46, color: _accent),
            ),
            const SizedBox(height: 22),
            Text(_query.isNotEmpty ? 'No notebooks found' : 'A fresh page awaits', style: GoogleFonts.lora(fontSize: 22, fontWeight: FontWeight.w700, color: _ink)),
            const SizedBox(height: 8),
            Text(
              _query.isNotEmpty ? 'Try another search, or clear the search field.' : 'Create your first notebook for class notes, sketches, or whatever you want to remember.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, height: 1.5, color: _muted),
            ),
            if (_query.isEmpty) ...[
              const SizedBox(height: 22),
              _createButton(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _notebookCard(Notebook notebook) {
    final cover = Color(notebook.colorValue);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _openNotebook(notebook),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFEAE6DC)),
            boxShadow: const [BoxShadow(color: Color(0x0C302F2A), blurRadius: 16, offset: Offset(0, 5))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(17)),
                  child: Stack(
                    children: [
                      Positioned.fill(child: ColoredBox(color: cover)),
                      Positioned(
                        right: 27,
                        top: 15,
                        child: Transform.rotate(
                          angle: 0.045,
                          child: Container(width: 125, height: 137, decoration: BoxDecoration(color: Colors.white.withAlpha(115), borderRadius: BorderRadius.circular(5))),
                        ),
                      ),
                      Positioned(
                        right: 40,
                        top: 22,
                        child: Transform.rotate(
                          angle: -0.035,
                          child: Container(
                            width: 126,
                            height: 137,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(color: const Color(0xFFFCFAF4), borderRadius: BorderRadius.circular(5), boxShadow: const [BoxShadow(color: Color(0x12000000), blurRadius: 10, offset: Offset(0, 4))]),
                            child: CustomPaint(painter: _MiniRulesPainter()),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 18,
                        top: 18,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(color: Colors.white.withAlpha(180), borderRadius: BorderRadius.circular(20)),
                          child: Row(children: [Icon(Icons.menu_book_rounded, size: 15, color: _accent), const SizedBox(width: 6), Text(notebook.isFavorite ? 'STARRED' : 'NOTEBOOK', style: const TextStyle(fontSize: 9, letterSpacing: 1.0, fontWeight: FontWeight.w700, color: _ink))]),
                        ),
                      ),
                      Positioned(
                        left: 13,
                        top: 13,
                        child: Container(width: 3, height: 165, decoration: BoxDecoration(color: Colors.black.withAlpha(15), borderRadius: BorderRadius.circular(3))),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(17, 12, 12, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(notebook.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.lora(fontSize: 16, fontWeight: FontWeight.w700, color: _ink)),
                          const SizedBox(height: 4),
                          Text('Edited ${_relativeDate(notebook.updatedAt)}', style: const TextStyle(fontSize: 11, color: _muted)),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Notebook actions',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _showNotebookMenu(notebook),
                      icon: const Icon(Icons.more_horiz_rounded, color: _muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showNotebookMenu(Notebook notebook) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _paper,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(leading: const Icon(Icons.drive_file_rename_outline_rounded), title: const Text('Rename'), onTap: () { Navigator.pop(context); _renameNotebook(notebook); }),
              ListTile(leading: Icon(notebook.isFavorite ? Icons.star_outline_rounded : Icons.star_rounded), title: Text(notebook.isFavorite ? 'Remove from starred' : 'Add to starred'), onTap: () { Navigator.pop(context); _toggleFavorite(notebook); }),
              ListTile(leading: const Icon(Icons.copy_all_rounded), title: const Text('Duplicate notebook'), onTap: () { Navigator.pop(context); _duplicateNotebook(notebook); }),
              ListTile(leading: const Icon(Icons.delete_outline_rounded, color: Color(0xFFB75D50)), title: const Text('Delete notebook', style: TextStyle(color: Color(0xFFB75D50))), onTap: () { Navigator.pop(context); _deleteNotebook(notebook); }),
            ],
          ),
        ),
      ),
    );
  }

  String _relativeDate(DateTime date) {
    final days = DateTime.now().difference(date).inDays;
    if (days <= 0) return 'today';
    if (days == 1) return 'yesterday';
    if (days < 7) return '$days days ago';
    return '${date.day}/${date.month}/${date.year}';
  }
}

class _MiniRulesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFFE7E0D2)..strokeWidth = 1;
    for (double y = 18; y < size.height; y += 16) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    canvas.drawLine(const Offset(13, 0), Offset(13, size.height), Paint()..color = const Color(0x32C77C70)..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(covariant _MiniRulesPainter oldDelegate) => false;
}
