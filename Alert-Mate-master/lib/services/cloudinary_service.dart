import 'dart:io';
import 'dart:typed_data';

import 'package:cloudinary_public/cloudinary_public.dart';
import 'package:http/http.dart' as http;

import '../constants/cloudinary_constants.dart';

class CloudinaryService {
  late final CloudinaryPublic _cloudinary;

  CloudinaryService()
      : _cloudinary = CloudinaryPublic(
          cloudinaryCloudName,
          cloudinaryUploadPreset,
          cache: false,
        );

  Future<String> uploadFile(File file, String folder) async {
    try {
      final response = await _cloudinary.uploadFile(
        CloudinaryFile.fromFile(
          file.path,
          folder: folder,
          resourceType: CloudinaryResourceType.Auto,
        ),
      );
      return response.secureUrl;
    } on CloudinaryException catch (e) {
      throw Exception('Cloudinary upload failed: ${e.message}');
    } catch (e) {
      throw Exception('Cloudinary upload failed: $e');
    }
  }

  Future<String> uploadBytes(Uint8List bytes, String fileName, String folder) async {
    try {
      final uri = Uri.parse(
        'https://api.cloudinary.com/v1_1/$cloudinaryCloudName/auto/upload',
      );

      final request = http.MultipartRequest('POST', uri)
        ..fields['upload_preset'] = cloudinaryUploadPreset
        ..fields['folder'] = folder
        ..files.add(
          http.MultipartFile.fromBytes(
            'file',
            bytes,
            filename: fileName,
          ),
        );

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Cloudinary upload failed (${response.statusCode}): ${response.body}');
      }

      final secureUrl = RegExp(r'"secure_url"\s*:\s*"([^"]+)"')
          .firstMatch(response.body)
          ?.group(1);
      if (secureUrl == null || secureUrl.isEmpty) {
        throw Exception('Cloudinary upload failed: secure_url missing');
      }
      return secureUrl.replaceAll(r'\/', '/');
    } catch (e) {
      throw Exception('Cloudinary upload failed: $e');
    }
  }
}

