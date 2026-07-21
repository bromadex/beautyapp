import '../supabase_client.dart';

class NotificationService {
  static Future<void> send({
    required String userId,
    required String type,
    required String title,
    required String body,
    String? referenceId,
  }) async {
    try {
      await supabase.from('notifications').insert({
        'user_id': userId,
        'type': type,
        'title': title,
        'body': body,
        'reference_id': referenceId,
      });
    } catch (_) {}
  }

  static Future<int> unreadCount(String userId) async {
    try {
      final data = await supabase
          .from('notifications')
          .select('id')
          .eq('user_id', userId)
          .eq('is_read', false);
      return (data as List).length;
    } catch (_) {
      return 0;
    }
  }
}
