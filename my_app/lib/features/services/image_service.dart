// lib/features/services/image_service.dart
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ImageService {
  ImageService._();
  static final instance = ImageService._();

  final _storage = FirebaseStorage.instance;

  /// Upload a meal image and return the download URL
  Future<String> uploadMealImage(File imageFile) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('User not authenticated');
    }

    try {
      // Create a unique filename with timestamp
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'meal_${user.uid}_$timestamp.jpg';
      
      // Create reference to Firebase Storage path
      final ref = _storage.ref().child('meal_images').child(fileName);
      
      // Upload the file
      final uploadTask = ref.putFile(imageFile);
      
      // Wait for upload to complete
      final snapshot = await uploadTask;
      
      // Get download URL
      final downloadUrl = await snapshot.ref.getDownloadURL();
      
      return downloadUrl;
    } catch (e) {
      throw Exception('Failed to upload image: $e');
    }
  }

  /// Delete a meal image from storage
  Future<void> deleteMealImage(String imageUrl) async {
    try {
      final ref = _storage.refFromURL(imageUrl);
      await ref.delete();
    } catch (e) {
      print('Failed to delete image: $e');
      // Don't throw error - image deletion failure shouldn't block other operations
    }
  }

  /// Get a reference to download an image (for caching purposes)
  Reference getImageReference(String imageUrl) {
    return _storage.refFromURL(imageUrl);
  }
}
