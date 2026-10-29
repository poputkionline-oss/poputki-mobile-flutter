import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../theme/app_theme.dart';

/// Review of a completed bus trip. The backend verifies boarding, so only the
/// booking id, rating and comment are sent.
class BusReviewDialog extends StatefulWidget {
  final int bookingId;
  const BusReviewDialog({super.key, required this.bookingId});

  @override
  State<BusReviewDialog> createState() => _BusReviewDialogState();
}

class _BusReviewDialogState extends State<BusReviewDialog> {
  final ApiClient _api = ApiClient();
  final TextEditingController _comment = TextEditingController();
  int _rating = 0;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating == 0) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await _api.post('/reviews/bus', data: {
        'booking_id': widget.bookingId,
        'rating': _rating,
        'comment': _comment.text,
      });
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      var message = 'Не удалось отправить отзыв. Повторите позже.';
      if (e is DioException && e.response?.data is Map) {
        message = (e.response!.data['message'] as String?) ?? message;
      }
      setState(() {
        _submitting = false;
        _error = message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Оставить отзыв',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
            const SizedBox(height: 4),
            const Text('Оцените поездку и перевозчика',
                style: TextStyle(fontSize: 13, color: Color(0xFF64748B))),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) {
                final star = i + 1;
                return IconButton(
                  onPressed: () => setState(() => _rating = star),
                  iconSize: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  icon: Icon(
                    Icons.star,
                    color: star <= _rating ? const Color(0xFFFBBF24) : const Color(0xFFE2E8F0),
                  ),
                );
              }),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _comment,
              maxLines: 3,
              maxLength: 2000,
              decoration: InputDecoration(
                hintText: 'Комментарий (необязательно)',
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                contentPadding: const EdgeInsets.all(12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: AppTheme.errorColor, fontSize: 12)),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
                    child: const Text('Отмена', style: TextStyle(color: Color(0xFF64748B))),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: (_rating == 0 || _submitting) ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Отправить', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
