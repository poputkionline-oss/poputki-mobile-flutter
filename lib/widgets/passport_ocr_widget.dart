import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import '../services/api_client.dart';

class PassportOCRWidget extends StatefulWidget {
  final Function(Map<String, dynamic>) onDataExtracted;

  const PassportOCRWidget({super.key, required this.onDataExtracted});

  @override
  State<PassportOCRWidget> createState() => _PassportOCRWidgetState();
}

class _PassportOCRWidgetState extends State<PassportOCRWidget> {
  static String get _ocrEndpoint => '${ApiClient.baseUrl}/ocr/scan';

  static const Map<String, String> _natMap = {
    'TJK': 'Таджикистан', 'TAJIKISTAN': 'Таджикистан',
    'RUS': 'Россия', 'RUSSIA': 'Россия',
    'UZB': 'Узбекистан', 'UZBEKISTAN': 'Узбекистан',
    'KAZ': 'Казахстан', 'KAZAKHSTAN': 'Казахстан',
    'KGZ': 'Кыргызстан', 'KYRGYZSTAN': 'Кыргызстан',
    'TKM': 'Туркменистан', 'TURKMENISTAN': 'Туркменистан',
    'BLR': 'Беларусь', 'BELARUS': 'Беларусь',
    'UKR': 'Украина', 'UKRAINE': 'Украина',
    'AZE': 'Азербайджан', 'AZERBAIJAN': 'Азербайджан',
    'ARM': 'Армения', 'ARMENIA': 'Армения',
    'GEO': 'Грузия', 'GEORGIA': 'Грузия',
  };

  final ImagePicker _picker = ImagePicker();
  bool _isScanning = false;

  /// Mirror the web's canvas compression: 1200×1200, quality ~0.6, target <200KB.
  Future<Uint8List?> _compress(String path) async {
    for (final quality in [60, 45, 30, 20]) {
      final bytes = await FlutterImageCompress.compressWithFile(
        path,
        minWidth: 1200,
        minHeight: 1200,
        quality: quality,
        format: CompressFormat.jpeg,
      );
      if (bytes == null) return null;
      if (bytes.lengthInBytes <= 200 * 1024) return bytes;
    }
    return await FlutterImageCompress.compressWithFile(
      path,
      minWidth: 1000,
      minHeight: 1000,
      quality: 15,
      format: CompressFormat.jpeg,
    );
  }

  Future<void> _pickAndScan(ImageSource source) async {
    final XFile? image = await _picker.pickImage(source: source);
    if (image == null) return;

    setState(() => _isScanning = true);

    try {
      Uint8List? bytes = await _compress(image.path);
      bytes ??= await File(image.path).readAsBytes();

      final base64Image = 'data:image/jpeg;base64,${base64Encode(bytes)}';

      final dio = Dio(BaseOptions(
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 30),
        responseType: ResponseType.json,
        validateStatus: (_) => true,
      ));

      final response = await dio.post(
        _ocrEndpoint,
        data: {
          'images': [base64Image]
        },
        options: Options(headers: {
          'Content-Type': 'application/json',
          'x-mana-man': 'nasa.2006'
        }),
      );

      final data = response.data is String
          ? jsonDecode(response.data as String) as Map<String, dynamic>
          : response.data as Map<String, dynamic>;

      if (data['status'] != 'OK') {
        throw Exception(data['message']?.toString() ?? 'Ошибка распознавания');
      }

      final resData = (data['data'] as Map?)?.cast<String, dynamic>() ?? {};
      const doc = (resData['document'] as Map?)?.cast<String, dynamic>() ?? {};

      // ---- Name parsing ----
      String lastName = (doc['surname'] ?? doc['lastName'] ?? doc['last_name'] ?? '').toString();
      String firstName = (doc['given_name'] ?? doc['givenName'] ?? doc['firstName'] ?? '').toString();
      String middleName = (doc['patronymic'] ?? doc['middleName'] ?? doc['middle_name'] ?? '').toString();

      // ---- Birth date ----
      final rawBirth = (doc['birth_date'] ?? doc['birthDay'] ?? doc['dateOfBirth'] ?? '').toString();
      String birthDate = '';
      if (rawBirth.contains('-')) {
        birthDate = rawBirth;
      } else if (rawBirth.length == 8) {
        birthDate = '${rawBirth.substring(0, 4)}-${rawBirth.substring(4, 6)}-${rawBirth.substring(6, 8)}';
      }

      // ---- Nationality ----
      final rawNat = ((doc['nationality'] ?? doc['country'] ?? '').toString()).toUpperCase();
      final citizenship = _natMap[rawNat] ?? (doc['nationality'] ?? doc['country'] ?? 'Таджикистан').toString();

      // ---- Doc number ----
      final docNum = (doc['document_number'] ?? doc['passportNumber'] ?? doc['doc_number'] ?? '').toString();

      // ---- Gender ----
      final rawGender = (doc['sex'] ?? doc['gender'] ?? '').toString().toUpperCase();
      final gender = (rawGender == 'M' || rawGender == 'MALE')
          ? 'male'
          : (rawGender == 'F' || rawGender == 'FEMALE')
              ? 'female'
              : '';

      widget.onDataExtracted({
        'lastName': lastName,
        'firstName': firstName,
        'middleName': middleName,
        'birthDate': birthDate,
        'gender': gender,
        'docNumber': docNum,
        'docType': (doc['document_type'] == 'id_card') ? 'ID-карта' : 'Загранпаспорт',
        'citizenship': citizenship,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Данные паспорта извлечены. Пожалуйста, проверьте их.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось распознать: $e. Заполните данные вручную.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  void _showSourcePicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Сделать фото'),
              onTap: () {
                Navigator.pop(context);
                _pickAndScan(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Выбрать из галереи'),
              onTap: () {
                Navigator.pop(context);
                _pickAndScan(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF2563EB), Color(0xFF9333EA)]),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
        child: InkWell(
          onTap: _isScanning ? null : _showSourcePicker,
          child: Column(
            children: [
              if (_isScanning) ...[
                const SizedBox(height: 10),
                const CircularProgressIndicator(strokeWidth: 3),
                const SizedBox(height: 16),
                const Text('Распознаем паспорт...', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
              ] else ...[
                const Icon(Icons.qr_code_scanner, color: Color(0xFF2563EB), size: 32),
                const SizedBox(height: 12),
                const Text('СКАНИРОВАТЬ ПАСПОРТ', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Color(0xFF2563EB))),
                const Text('Автоматическое заполнение данных', style: TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
