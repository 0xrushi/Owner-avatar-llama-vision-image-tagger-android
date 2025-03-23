import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(MyApp());
}

/// A simple model to wrap each image file with a selection flag.
class ImageItem {
  final File file;
  bool selected;
  ImageItem(this.file, {this.selected = false});
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Image Folder Browser',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
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
  
  @override
  void initState() {
    super.initState();
    _getAndroidVersion();
    _checkPermissions();
  }
  
  Future<void> _getAndroidVersion() async {
    if (Platform.isAndroid) {
      _androidVersion = int.tryParse(Platform.operatingSystemVersion.split(' ').last) ?? 0;
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

    if (1==2) {
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

  Future<void> _pickFolder() async {
    bool hasPermission = await _requestPermissions();
    
    if (!hasPermission) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Storage permission required"),
          action: _permissionPermanentlyDenied 
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
      // For older Android versions, use a custom directory selection approach
      if (Platform.isAndroid && _androidVersion < 11) {
        await _showDirectoryPicker();
      } else {
        // Use file_selector for newer Android versions and other platforms
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
    // A simple directory picker for older Android versions.
    List<Directory> storageDirectories = [];
    
    try {
      storageDirectories = await getExternalStorageDirectories() ?? [];
    } catch (e) {
      final appDocDir = await getApplicationDocumentsDirectory();
      storageDirectories.add(appDocDir);
    }
    
    // Try to add common directories like DCIM, Pictures, and Download
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
      // Ignore if these directories aren't accessible
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
                      subtitle: Text(dir.path, maxLines: 1, overflow: TextOverflow.ellipsis),
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
      _selectAll = false; // reset select all
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

  /// Deletes all images that have been selected.
  Future<void> _deleteSelectedImages() async {
    final selectedItems = _images.where((img) => img.selected).toList();
    if (selectedItems.isEmpty) return;

    bool confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Confirm Deletion"),
        content: Text("Are you sure you want to delete ${selectedItems.length} selected image(s)?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text("Delete")),
        ],
      ),
    ) ?? false;

    if (!confirmed) return;

    for (var image in selectedItems) {
      try {
        await image.file.delete();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to delete: ${p.basename(image.file.path)}")),
        );
      }
    }

    setState(() {
      _images.removeWhere((img) => img.selected);
      _selectAll = false;
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Selected images deleted")),
    );
  }

  /// Toggle select all functionality.
  void _toggleSelectAll(bool? value) {
    setState(() {
      _selectAll = value ?? false;
      _images.forEach((img) {
        img.selected = _selectAll;
      });
    });
  }

  /// When an individual image checkbox is toggled, update its state and check if all images are selected.
  void _toggleImageSelection(int index, bool? value) {
    setState(() {
      _images[index].selected = value ?? false;
      // Update select all checkbox if needed.
      _selectAll = _images.every((img) => img.selected);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentDirectory != null 
            ? "Images: ${p.basename(_currentDirectory!)}" 
            : "Image Folder Browser"),
        actions: [
          IconButton(
            icon: Icon(Icons.folder_open),
            onPressed: _pickFolder,
          ),
        ],
      ),
      body: _isLoading 
          ? Center(child: CircularProgressIndicator())
          : _images.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.photo_library_outlined, size: 64, color: Colors.grey),
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
                        )
                      ]
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Select All and Delete Selected controls
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: Row(
                        children: [
                          Checkbox(
                            value: _selectAll,
                            onChanged: _toggleSelectAll,
                          ),
                          Text("Select All"),
                          Spacer(),
                          if (_images.any((img) => img.selected))
                            ElevatedButton.icon(
                              onPressed: _deleteSelectedImages,
                              icon: Icon(Icons.delete),
                              label: Text("Delete Selected (${_images.where((img) => img.selected).length})"),
                            ),
                        ],
                      ),
                    ),
                    // Image grid
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
                                      child: Icon(Icons.broken_image, color: Colors.red),
                                    );
                                  },
                                ),
                              ),
                              // Checkbox overlay in the top-left corner.
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
                                    onChanged: (value) => _toggleImageSelection(index, value),
                                    activeColor: Colors.blue,
                                    checkColor: Colors.white,
                                  ),
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
