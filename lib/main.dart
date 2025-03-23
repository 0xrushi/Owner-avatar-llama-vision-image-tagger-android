import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(MyApp());
}

/// Extended model to hold processing metadata.
class ImageItem {
  final File file;
  bool selected;
  bool isProcessed;
  String? description;
  List<String>? tags;
  String? textContent;

  ImageItem(
    this.file, {
    this.selected = false,
    this.isProcessed = false,
    this.description,
    this.tags,
    this.textContent,
  });
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Image Folder Browser',
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      ),
      home: ImageFolderScreen(),
    );
  }
}

class ImageFolderScreen extends StatefulWidget {
  @override
  _ImageFolderScreenState createState() => _ImageFolderScreenState();
}

class _ImageFolderScreenState extends State<ImageFolderScreen> {
  List<ImageItem> _images = [];
  String? _currentDirectory;
  bool _permissionPermanentlyDenied = false;
  bool _isLoading = false;
  int _androidVersion = 0;
  bool _selectAll = false;

  // State for search and processing
  String _searchQuery = "";
  bool _processingAll = false;
  int _processedCount = 0;
  int _totalToProcess = 0;
  String _currentImageName = "";
  List<String> _failedImages = [];

  // Notifiers for progress and logging.
  final ValueNotifier<double> _progressNotifier = ValueNotifier(0.0);
  final ValueNotifier<List<String>> _logMessages = ValueNotifier([]);
  final ValueNotifier<String?> _finalStatusMessage = ValueNotifier(null);
  bool _isLogDialogOpen = false;

  // Mutable API base URL; this is updated via the Settings page.
  String _apiBaseUrl = "http://10.0.0.175:8000";

  // Derived API endpoint URLs.
  String get _processApiUrl => "$_apiBaseUrl/process-image";
  String get _searchApiUrl => "$_apiBaseUrl/search";

  @override
  void initState() {
    super.initState();
    _getAndroidVersion();
    _checkPermissions();
  }

  Future<void> _getAndroidVersion() async {
    if (Platform.isAndroid) {
      _androidVersion =
          int.tryParse(Platform.operatingSystemVersion.split(' ').last) ?? 0;
    }
  }

  Future<void> _checkPermissions() async {
    if (Platform.isAndroid) {
      PermissionStatus status = await Permission.storage.status;
      if (status.isPermanentlyDenied) {
        setState(() {
          _permissionPermanentlyDenied = true;
        });
      }
    }
  }

  Future<bool> _requestPermissions() async {
    if (!Platform.isAndroid) return true;
    if (1 == 2) {
      var status = await Permission.storage.status;
      if (status.isGranted) return true;
      final newStatus = await Permission.storage.request();
      if (newStatus.isPermanentlyDenied) {
        setState(() {
          _permissionPermanentlyDenied = true;
        });
      }
      return newStatus.isGranted;
    } else {
      var status = await Permission.manageExternalStorage.status;
      if (status.isGranted) return true;
      final newStatus = await Permission.manageExternalStorage.request();
      if (newStatus.isPermanentlyDenied) {
        setState(() {
          _permissionPermanentlyDenied = true;
        });
      }
      return newStatus.isGranted;
    }
  }

  void _openAppSettings() async {
    await openAppSettings();
  }

  /// Opens the persistent log dialog if not already open.
  void _openLogDialog() {
    if (_isLogDialogOpen) return; // Already open.
    _isLogDialogOpen = true;
    showDialog(
      context: context,
      barrierDismissible: false, // force user to use close button
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          backgroundColor: Colors.grey[900],
          insetPadding: EdgeInsets.all(16),
          child: Container(
            width: double.infinity,
            height: 400,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header with title and close button.
                Container(
                  decoration: BoxDecoration(
                    color: Colors.indigo,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(12),
                    ),
                  ),
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Processing Log",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: Colors.white),
                        onPressed: () {
                          Navigator.of(context).pop();
                          _isLogDialogOpen = false;
                        },
                      ),
                    ],
                  ),
                ),
                // Progress area.
                if (_processingAll)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Processing: $_currentImageName",
                          style: TextStyle(color: Colors.white70, fontSize: 16),
                        ),
                        SizedBox(height: 4),
                        ValueListenableBuilder<double>(
                          valueListenable: _progressNotifier,
                          builder: (context, progress, child) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                LinearProgressIndicator(
                                  value: progress,
                                  backgroundColor: Colors.grey[700],
                                ),
                                SizedBox(height: 4),
                                Text(
                                  "$_processedCount / $_totalToProcess processed",
                                  style: TextStyle(color: Colors.white60),
                                ),
                                if (_failedImages.isNotEmpty)
                                  Text(
                                    "Failed: ${_failedImages.length}",
                                    style: TextStyle(
                                      color: Colors.redAccent,
                                      fontSize: 16,
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),

                        SizedBox(height: 4),
                      ],
                    ),
                  ),
                // Scrollable log messages.
                Expanded(
                  child: Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.vertical(
                        bottom: Radius.circular(12),
                      ),
                    ),
                    child: Scrollbar(
                      child: SingleChildScrollView(
                        child: ValueListenableBuilder<List<String>>(
                          valueListenable: _logMessages,
                          builder: (context, logs, child) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children:
                                  logs
                                      .map(
                                        (log) => Text(
                                          log,
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontFamily: 'Courier',
                                          ),
                                        ),
                                      )
                                      .toList(),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                // Final status message area.
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[800],
                    borderRadius: BorderRadius.vertical(
                      bottom: Radius.circular(12),
                    ),
                  ),
                  child: ValueListenableBuilder<String?>(
                    valueListenable: _finalStatusMessage,
                    builder: (context, finalMsg, child) {
                      return Text(
                        finalMsg ?? "",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color:
                              finalMsg != null && finalMsg.contains("ERROR")
                                  ? Colors.redAccent
                                  : Colors.greenAccent,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ).then((_) {
      // When the dialog is closed, clear logs if needed.
      _isLogDialogOpen = false;
    });
  }

  /// Appends a log message.
  void _appendLog(String message) {
    _logMessages.value = List.from(_logMessages.value)..add(message);
  }

  /// Sets the final status message.
  void _setFinalStatus(String message) {
    _finalStatusMessage.value = message;
  }

  Future<void> _pickFolder() async {
    bool hasPermission = await _requestPermissions();
    if (!hasPermission) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Storage permission required"),
          action:
              _permissionPermanentlyDenied
                  ? SnackBarAction(
                    label: 'SETTINGS',
                    onPressed: _openAppSettings,
                  )
                  : null,
        ),
      );
      return;
    }
    try {
      if (Platform.isAndroid && _androidVersion < 11) {
        await _showDirectoryPicker();
      } else {
        String? selectedDirectory = await getDirectoryPath();
        if (selectedDirectory != null) {
          _currentDirectory = selectedDirectory;
          await _loadImagesFromDirectory(selectedDirectory);
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error picking folder: ${e.toString()}")),
      );
    }
  }

  Future<void> _showDirectoryPicker() async {
    List<Directory> storageDirectories = [];
    try {
      storageDirectories = await getExternalStorageDirectories() ?? [];
    } catch (e) {
      final appDocDir = await getApplicationDocumentsDirectory();
      storageDirectories.add(appDocDir);
    }
    try {
      if (await Directory('/storage/emulated/0/DCIM').exists()) {
        storageDirectories.add(Directory('/storage/emulated/0/DCIM'));
      }
      if (await Directory('/storage/emulated/0/Pictures').exists()) {
        storageDirectories.add(Directory('/storage/emulated/0/Pictures'));
      }
      if (await Directory('/storage/emulated/0/Download').exists()) {
        storageDirectories.add(Directory('/storage/emulated/0/Download'));
      }
    } catch (e) {
      // Ignore if inaccessible.
    }
    final selectedDir = await showModalBottomSheet<Directory>(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  'Select Folder',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                tileColor: Colors.grey[200],
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: storageDirectories.length,
                  itemBuilder: (context, index) {
                    final dir = storageDirectories[index];
                    String displayName = dir.path.split('/').last;
                    if (displayName.isEmpty) {
                      displayName = dir.path;
                    }
                    return ListTile(
                      leading: Icon(Icons.folder),
                      title: Text(displayName),
                      subtitle: Text(
                        dir.path,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () {
                        Navigator.of(context).pop(dir);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
    if (selectedDir != null) {
      _currentDirectory = selectedDir.path;
      await _loadImagesFromDirectory(selectedDir.path);
    }
  }

  Future<void> _loadImagesFromDirectory(String directoryPath) async {
    setState(() {
      _isLoading = true;
      _selectAll = false;
      _searchQuery = "";
    });
    try {
      final dir = Directory(directoryPath);
      final List<ImageItem> imageItems = [];
      await for (var entity in dir.list()) {
        if (entity is File && _isImage(entity.path)) {
          imageItems.add(ImageItem(entity));
        }
      }
      setState(() {
        _images = imageItems;
        _isLoading = false;
      });
      if (imageItems.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("No images found in this folder")),
        );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error loading images: ${e.toString()}")),
      );
    }
  }

  bool _isImage(String path) {
    final ext = p.extension(path).toLowerCase();
    return ['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp'].contains(ext);
  }

  Future<void> _deleteSelectedImages() async {
    final selectedItems = _images.where((img) => img.selected).toList();
    if (selectedItems.isEmpty) return;
    bool confirmed =
        await showDialog<bool>(
          context: context,
          builder:
              (context) => AlertDialog(
                title: Text("Confirm Deletion"),
                content: Text(
                  "Are you sure you want to delete ${selectedItems.length} selected image(s)?",
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text("Cancel"),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text("Delete"),
                  ),
                ],
              ),
        ) ??
        false;
    if (!confirmed) return;
    for (var image in selectedItems) {
      try {
        await image.file.delete();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to delete: ${p.basename(image.file.path)}"),
          ),
        );
      }
    }
    setState(() {
      _images.removeWhere((img) => img.selected);
      _selectAll = false;
    });
    _appendLog("SUCCESS: Selected images deleted");
  }

  void _toggleSelectAll(bool? value) {
    setState(() {
      _selectAll = value ?? false;
      _images.forEach((img) {
        img.selected = _selectAll;
      });
    });
  }

  void _toggleImageSelection(int index, bool? value) {
    setState(() {
      _images[index].selected = value ?? false;
      _selectAll = _images.every((img) => img.selected);
    });
  }

  Future<void> _processImage(ImageItem image) async {
    try {
      _openLogDialog();
      _appendLog("Processing ${p.basename(image.file.path)}...");
      var uri = Uri.parse(_processApiUrl);
      var request = http.MultipartRequest('POST', uri);
      request.files.add(
        await http.MultipartFile.fromPath('image', image.file.path),
      );
      var streamedResponse = await request.send();
      if (streamedResponse.statusCode == 200) {
        final respStr = await streamedResponse.stream.bytesToString();
        final data = json.decode(respStr);
        setState(() {
          image.description = data['description'];
          image.tags =
              data['tags'] != null ? List<String>.from(data['tags']) : [];
          image.textContent = data['text_content'];
          image.isProcessed = data['is_processed'] ?? true;
        });
        _appendLog(
          "SUCCESS: Processed ${p.basename(image.file.path)} successfully",
        );
      } else {
        throw Exception(
          "Processing failed (status ${streamedResponse.statusCode})",
        );
      }
    } catch (e) {
      _appendLog("ERROR: ${p.basename(image.file.path)}: ${e.toString()}");
      throw Exception(
        "Error processing ${p.basename(image.file.path)}: ${e.toString()}",
      );
    }
  }

  Future<void> _processAllImages() async {
    final unprocessedImages = _images.where((img) => !img.isProcessed).toList();

    if (unprocessedImages.isEmpty) {
      _openLogDialog();
      _appendLog("ERROR: No unprocessed images found!");
      return;
    }

    _openLogDialog();
    setState(() {
      _processingAll = true;
      _currentImageName = "";
      _processedCount = 0;
      _totalToProcess = unprocessedImages.length;
      _failedImages = [];
      _logMessages.value = [];
      _finalStatusMessage.value = null;
      _progressNotifier.value = 0.0;
    });

    for (var image in unprocessedImages) {
      setState(() {
        _currentImageName = p.basename(image.file.path);
      });

      try {
        await _processImage(image);
      } catch (e) {
        _appendLog("ERROR: ${p.basename(image.file.path)} failed: $e");
        _failedImages.add(p.basename(image.file.path));
      } finally {
        setState(() {
          image.isProcessed = false;
          _processedCount++;
          _progressNotifier.value =
              _totalToProcess == 0 ? 0.0 : _processedCount / _totalToProcess;
        });
      }
    }

    setState(() {
      _processingAll = false;
      _currentImageName = "";
    });

    if (_failedImages.isNotEmpty) {
      _setFinalStatus(
        "Processing complete with ${_failedImages.length} failures",
      );
    } else {
      _setFinalStatus("Processing complete successfully!");
    }
  }

  Future<void> _refreshImages() async {
    if (_currentDirectory != null) {
      await _loadImagesFromDirectory(_currentDirectory!);
      _appendLog("SUCCESS: Images refreshed");
    }
  }

  Future<void> _searchImages() async {
    if (_searchQuery.isEmpty) {
      await _refreshImages();
      return;
    }
    try {
      _openLogDialog();
      _appendLog("Searching for '$_searchQuery'...");
      setState(() {
        _isLoading = true;
      });
      final response = await http.post(
        Uri.parse(_searchApiUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"query": _searchQuery}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final imagesData = data['images'] as List;
        setState(() {
          _images =
              imagesData.map<ImageItem>((img) {
                final filePath = p.join(_currentDirectory!, img['path']);
                return ImageItem(
                  File(filePath),
                  selected: false,
                  isProcessed: img['is_processed'] ?? false,
                  description: img['description'],
                  tags:
                      img['tags'] != null ? List<String>.from(img['tags']) : [],
                  textContent: img['text_content'],
                );
              }).toList();
        });
        _appendLog(
          "SUCCESS: Search successful, found ${_images.length} image(s)",
        );
      } else {
        throw Exception("Error searching images: ${response.statusCode}");
      }
    } catch (e) {
      _appendLog("ERROR: Search failed: ${e.toString()}");
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Opens the Settings page.
  Future<void> _openSettings() async {
    final newUrl = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SettingsPage(apiBaseUrl: _apiBaseUrl),
      ),
    );
    if (newUrl != null && newUrl is String) {
      setState(() {
        _apiBaseUrl = newUrl;
      });
      _appendLog("SUCCESS: API Base URL updated to $_apiBaseUrl");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _currentDirectory != null
              ? "Images: ${p.basename(_currentDirectory!)}"
              : "Image Folder Browser",
        ),
        actions: [
          IconButton(icon: Icon(Icons.folder_open), onPressed: _pickFolder),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: Colors.indigo),
              child: Text(
                "Settings",
                style: TextStyle(color: Colors.white, fontSize: 24),
              ),
            ),
            ListTile(
              leading: Icon(Icons.settings),
              title: Text("API Settings"),
              onTap: () {
                Navigator.pop(context); // Close the drawer.
                _openSettings();
              },
            ),
          ],
        ),
      ),
      body:
          _isLoading
              ? Center(child: CircularProgressIndicator())
              : _images.isEmpty
              ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.photo_library_outlined,
                      size: 64,
                      color: Colors.grey,
                    ),
                    SizedBox(height: 16),
                    Text(
                      _currentDirectory == null
                          ? "Select a folder to view images"
                          : "No images found in this folder",
                      style: TextStyle(fontSize: 18, color: Colors.grey[700]),
                    ),
                    SizedBox(height: 16),
                    ElevatedButton.icon(
                      icon: Icon(Icons.folder_open),
                      label: Text("Select Folder"),
                      onPressed: _pickFolder,
                    ),
                    if (_permissionPermanentlyDenied) ...[
                      SizedBox(height: 16),
                      Text(
                        "Storage permission was denied",
                        style: TextStyle(color: Colors.red),
                      ),
                      TextButton(
                        onPressed: _openAppSettings,
                        child: Text("Open Settings"),
                      ),
                    ],
                  ],
                ),
              )
              : Column(
                children: [
                  // Top control area.
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Wrap(
                      alignment: WrapAlignment.start,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        // Search text field.
                        Container(
                          width: 200,
                          child: TextField(
                            decoration: InputDecoration(
                              hintText: "Search images...",
                              border: OutlineInputBorder(),
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 10,
                              ),
                              filled: true,
                              fillColor: Colors.grey[100],
                            ),
                            onChanged: (value) {
                              setState(() {
                                _searchQuery = value;
                              });
                            },
                          ),
                        ),
                        // Search button.
                        ElevatedButton.icon(
                          onPressed: _searchImages,
                          icon: Icon(Icons.search),
                          label: Text("Search"),
                        ),
                        // Refresh button.
                        ElevatedButton.icon(
                          onPressed: _refreshImages,
                          icon: Icon(Icons.refresh),
                          label: Text("Refresh"),
                        ),
                        // Process All button.
                        ElevatedButton.icon(
                          onPressed: _processingAll ? null : _processAllImages,
                          icon: Icon(Icons.flash_on),
                          label: Text("Process All"),
                        ),
                        // Select All checkbox.
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Checkbox(
                              value: _selectAll,
                              onChanged: _toggleSelectAll,
                            ),
                            Text("Select All"),
                          ],
                        ),
                        // Delete Selected button.
                        if (_images.any((img) => img.selected))
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                            ),
                            onPressed: _deleteSelectedImages,
                            icon: Icon(Icons.delete),
                            label: Text(
                              "Delete Selected (${_images.where((img) => img.selected).length})",
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Image grid.
                  Expanded(
                    child: GridView.builder(
                      padding: EdgeInsets.all(8),
                      itemCount: _images.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 4,
                        mainAxisSpacing: 4,
                      ),
                      itemBuilder: (context, index) {
                        final imageItem = _images[index];
                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: Image.file(
                                imageItem.file,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    color: Colors.grey[300],
                                    child: Icon(
                                      Icons.broken_image,
                                      color: Colors.red,
                                    ),
                                  );
                                },
                              ),
                            ),
                            // Checkbox overlay.
                            Positioned(
                              top: 4,
                              left: 4,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black45,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Checkbox(
                                  value: imageItem.selected,
                                  onChanged: (value) {
                                    int realIndex = _images.indexWhere(
                                      (img) => p.equals(
                                        img.file.path,
                                        imageItem.file.path,
                                      ),
                                    );
                                    _toggleImageSelection(realIndex, value);
                                  },
                                  activeColor: Colors.blue,
                                  checkColor: Colors.white,
                                ),
                              ),
                            ),
                            // Processed indicator.
                            if (imageItem.isProcessed)
                              Positioned(
                                bottom: 4,
                                right: 4,
                                child: Icon(
                                  Icons.check_circle,
                                  color: Colors.green,
                                  size: 20,
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  final String apiBaseUrl;
  SettingsPage({required this.apiBaseUrl});

  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late TextEditingController _controller;
  bool _isTesting = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.apiBaseUrl);
  }

  Future<void> _testApi() async {
    setState(() {
      _isTesting = true;
    });
    final url = _controller.text.trim();
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("API is working!")));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "API test failed with status: ${response.statusCode}",
            ),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("API test error: ${e.toString()}")),
      );
    } finally {
      setState(() {
        _isTesting = false;
      });
    }
  }

  void _saveSettings() {
    Navigator.pop(context, _controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("API Settings")),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                labelText: "API Base URL",
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 16),
            Row(
              children: [
                ElevatedButton(
                  onPressed: _isTesting ? null : _testApi,
                  child:
                      _isTesting
                          ? CircularProgressIndicator()
                          : Text("Test API"),
                ),
                SizedBox(width: 16),
                ElevatedButton(onPressed: _saveSettings, child: Text("Save")),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
