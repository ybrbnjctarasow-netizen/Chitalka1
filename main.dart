import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:rar/rar.dart';
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Комикс Читалка',
      theme: ThemeData.dark(),
      home: const ComicReaderHome(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class ComicReaderHome extends StatefulWidget {
  const ComicReaderHome({super.key});
  @override
  State<ComicReaderHome> createState() => _ComicReaderHomeState();
}

class _ComicReaderHomeState extends State<ComicReaderHome> {
  List<String> _pages = [];
  String? _comicName;
  bool _isLoading = false;
  String _status = 'Выберите файл или папку';

  // Выбор одного файла
  Future<void> _pickFile() async {
    await _clearCurrentComic();
    _pickAndOpenFile(allowMultiple: false);
  }

  // Выбор папки
  Future<void> _pickDirectory() async {
    await _clearCurrentComic();
    setState(() => _isLoading = true);

    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

      if (selectedDirectory == null) {
        setState(() => _isLoading = false);
        return;
      }

      final dir = Directory(selectedDirectory);
      final files = dir.listSync().whereType<File>().where((f) {
        final ext = p.extension(f.path).toLowerCase();
        return ['.cbr', '.cbz', '.rar', '.zip'].contains(ext);
      }).toList();

      if (files.isEmpty) {
        setState(() => _status = 'В папке не найдено комиксов');
        return;
      }

      // Открываем первый найденный файл
      await _openComicFile(files.first);
    } catch (e) {
      setState(() => _status = 'Ошибка: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickAndOpenFile({bool allowMultiple = false}) async {
    setState(() => _isLoading = true);

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['cbr', 'rar', 'cbz', 'zip'],
        allowMultiple: allowMultiple,
      );

      if (result == null || result.files.isEmpty) return;

      await _openComicFile(File(result.files.single.path!));
    } catch (e) {
      setState(() => _status = 'Ошибка открытия: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _openComicFile(File file) async {
    _comicName = p.basenameWithoutExtension(file.path);
    final extension = p.extension(file.path).toLowerCase();

    setState(() => _status = 'Распаковка...');

    final tempDir = await getTemporaryDirectory();
    final extractPath = Directory('${tempDir.path}/$_comicName');
    if (extractPath.existsSync()) extractPath.deleteSync(recursive: true);
    extractPath.createSync(recursive: true);

    List<String> imagePaths = [];

    try {
      final bytes = await file.readAsBytes();

      if (['.cbr', '.rar'].contains(extension)) {
        final rarFile = RarFile(bytes);
        final archive = rarFile.extract();
        imagePaths = await _saveImages(archive, extractPath);
      } else {
        final archive = ZipDecoder().decodeBytes(bytes);
        imagePaths = await _saveImages(archive, extractPath);
      }

      imagePaths.sort((a, b) => a.compareTo(b));

      setState(() {
        _pages = imagePaths;
        _status = '${_pages.length} страниц';
      });
    } catch (e) {
      setState(() => _status = 'Не удалось открыть файл: $e');
    }
  }

  Future<List<String>> _saveImages(dynamic archive, Directory extractPath) async {
    List<String> paths = [];
    for (var file in archive.files) {
      if (file.isFile) {
        final ext = p.extension(file.name).toLowerCase();
        if (['.jpg', '.jpeg', '.png', '.webp'].contains(ext)) {
          final filePath = '${extractPath.path}/${p.basename(file.name)}';
          final output = File(filePath);
          await output.writeAsBytes(file.content as List<int>);
          paths.add(filePath);
        }
      }
    }
    return paths;
  }

  Future<void> _clearCurrentComic() async {
    setState(() {
      _pages.clear();
      _comicName = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_comicName ?? 'Комикс Читалка'),
        actions: [
          IconButton(icon: const Icon(Icons.folder_open), onPressed: _pickFile),
          IconButton(icon: const Icon(Icons.folder), onPressed: _pickDirectory),
          if (_pages.isNotEmpty)
            IconButton(icon: const Icon(Icons.close), onPressed: _clearCurrentComic),
        ],
      ),
      body: _isLoading
          ? Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [const CircularProgressIndicator(), const SizedBox(height: 16), Text(_status)],
            ))
          : _pages.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.book, size: 120, color: Colors.grey),
                      const SizedBox(height: 20),
                      Text(_status, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18)),
                      const SizedBox(height: 30),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton.icon(onPressed: _pickFile, icon: const Icon(Icons.file_open), label: const Text('Файл')),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(onPressed: _pickDirectory, icon: const Icon(Icons.folder), label: const Text('Папку')),
                        ],
                      ),
                    ],
                  ),
                )
              : PhotoViewGallery.builder(
                  scrollPhysics: const BouncingScrollPhysics(),
                  scrollDirection: Axis.vertical,           // ← Вертикальное пролистывание
                  itemCount: _pages.length,
                  builder: (context, index) {
                    return PhotoViewGalleryPageOptions(
                      imageProvider: FileImage(File(_pages[index])),
                      initialScale: PhotoViewComputedScale.contained,
                      minScale: PhotoViewComputedScale.contained * 0.8,
                      maxScale: PhotoViewComputedScale.covered * 4.0,
                    );
                  },
                  loadingBuilder: (context, event) => const Center(child: CircularProgressIndicator()),
                ),
    );
  }
}
